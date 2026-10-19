--[[
@module  ui_cam
@summary 摄像头：UVC 拍照（上电 → 抓一帧 → 显示 / 存卡 → 释放）
@version 1.0
@date    2026.10.18
@usage
    sys.publish("OPEN_CAM_WIN")

说明
1. 硬件是 UVC 摄像头（AirCAMERA_1030/1031），供电脚取自 config 的 hw.cam.en（UVC_EN=GPIO29）；
2. 不做实时预览：UVC 逐帧刷 RGB 屏掉帧严重，只做"拍一张 + 显示结果"；
3. 拍照结果先落 /ram/cam.jpg，再按需复制到 SD 卡（/sd/cam_HHMMSS.jpg）；
4. 拍照是耗时操作（上电 0.2s + 枚举 0.8s + 抓帧），全程在 task 里跑，界面不会卡死；
5. 页面关闭时若摄像头仍开着会 close()，避免 USB 一直被占用。
6. 预览卡里的提示文字 / 照片四周统一内缩 FRAME_PAD(6px)：卡片有 1px 描边，
   子控件与描边后的内容区齐平就会让 LVGL 在卡片底边/右边画滚动条（全工程同一套处理）。

布局（设计坐标，基准 800×480）
    y 16   预览卡（760×300）：显示照片，没照片时显示提示；内部四周留 6px
    y 326  状态行（两行小字：耗时 / 文件大小 / 保存路径）
    y 372  按钮行：拍照 / 存到 SD 卡 / 清除（高度 46，不贴 body 底边）
]]

local exwin = require "exwin"
local ui    = require "ui_kit"
local T     = require "ui_theme"

local C, F, S, G = T.COLOR, T.FONT, T.SCREEN, T.GAP

-- ===== 设计坐标布局 =====
local PAD    = G.M
local BODY_W = S.DW - PAD * 2
local VIEW_Y = 16
local VIEW_H = 300
local VIEW_W = BODY_W
local FRAME_PAD = 6
local NOTE_Y = VIEW_Y + VIEW_H + 10
local BTN_Y  = NOTE_Y + 46          -- 按钮行
local BTN_H  = 46                   -- 46 而不是 48：给 body 底边留 4px 缓冲（贴边会画滚动条）
local BTN_W  = 235

local SAVE_PATH = "/ram/cam.jpg"
local W, H      = 640, 480

local win_id, page
local view_card, view_img, hint_label, status_label
local busy = false          -- 正在拍照（防重复点击）
local opened = false        -- excamera 是否已 open
local last_size = 0

local function cam_cfg()
    return ((_G.project_config or {}).hw or {}).cam or {}
end

local function set_status(text, color)
    if not status_label then return end
    status_label:set_text(text)
    pcall(function() status_label:set_color(color or C.TEXT_WEAK) end)
end

--- 文件大小（读不到返回 0）
local function file_size(path)
    local fp = io.open(path, "rb")
    if not fp then return 0 end
    local sz = fp:seek("end") or 0
    fp:close()
    return sz
end

--- 把已拍的 /ram/cam.jpg 复制到 SD 卡，返回目标路径 / nil
local function copy_to_sd()
    local name = os.date("/sd/cam_%H%M%S.jpg")
    local src = io.open(SAVE_PATH, "rb")
    if not src then return nil end
    local dst = io.open(name, "wb")
    if not dst then
        src:close()
        return nil
    end
    while true do
        local blk = src:read(4096)
        if not blk or #blk == 0 then break end
        dst:write(blk)
    end
    src:close()
    dst:close()
    return name
end

local function create_ui()
    page = ui.page({
        title   = "摄像头",
        on_back = function() if win_id then exwin.close(win_id) end end,
    })

    -- ===== 预览卡：白底 + 照片 / 提示 =====
    view_card = ui.card({
        parent = page.body, x = PAD, y = VIEW_Y, w = VIEW_W, h = VIEW_H,
        color = C.BG, border = C.BORDER,
    })
    hint_label = ui.label({
        -- 内缩 FRAME_PAD：和卡片描边后的内容区保持距离，否则卡片会画滚动条
        parent = view_card, x = FRAME_PAD, y = math.floor(VIEW_H / 2) - 30,
        w = VIEW_W - FRAME_PAD * 2, h = 60,
        text = "点下方「拍照」抓一帧",
        size = F.NORMAL, color = C.TEXT_WEAK, align = airui.TEXT_ALIGN_CENTER,
    })

    -- ===== 状态行 =====
    status_label = ui.label({
        parent = page.body, x = PAD, y = NOTE_Y, w = BODY_W, h = 42,
        text = "",
        size = F.TINY, color = C.TEXT_WEAK,
    })

    -- ===== 按钮 =====
    ui.button({
        parent = page.body, x = PAD, y = BTN_Y, w = BTN_W, h = BTN_H, text = "拍照",
        on_click = function() sys.publish("CAM_SHOT") end,
    })
    ui.button({
        parent = page.body, x = PAD * 2 + BTN_W, y = BTN_Y, w = BTN_W, h = BTN_H,
        text = "存到 SD 卡",
        color = C.PRIMARY_SOFT, text_color = C.PRIMARY,
        on_click = function() sys.publish("CAM_SAVE_SD") end,
    })
    ui.button({
        parent = page.body, x = PAD * 3 + BTN_W * 2, y = BTN_Y, w = S.DW - PAD * 4 - BTN_W * 2, h = BTN_H,
        text = "清除",
        color = C.DISABLED,
        on_click = function() sys.publish("CAM_CLEAR") end,
    })
end

-- ===== 显示 =====

local function show_photo()
    if view_img then
        pcall(function() view_img:destroy() end)
        view_img = nil
    end

    local ok, img = pcall(airui.image, {
        -- 图片和提示文字一样内缩 FRAME_PAD：贴到卡片内容区边缘会触发卡片画滚动条
        parent = view_card, x = FRAME_PAD, y = FRAME_PAD,
        w = VIEW_W - FRAME_PAD * 2, h = VIEW_H - FRAME_PAD * 2, src = SAVE_PATH,
    })
    if ok and img then
        view_img = img
        if hint_label then hint_label:set_text("") end
        return true
    end

    if hint_label then
        hint_label:set_text("已拍照（当前固件不能显示 JPEG）\n文件：" .. SAVE_PATH)
    end
    return false
end

-- ===== 拍照 =====

local function do_shot()
    if busy or not page then return end
    busy = true
    set_status("正在给摄像头上电（UVC_EN）…", C.TEXT)

    sys.taskInit(function()
        local cfg = cam_cfg()
        local ok_lib, excamera = pcall(require, "excamera")
        if not ok_lib then
            set_status("扩展库 excamera 不可用（固件未带）", C.DANGER)
            busy = false
            return
        end

        -- 断电复位：先拉低断掉摄像头供电，再上电等供电稳定 + USB 枚举
        if cfg.en then
            pcall(gpio.setup, cfg.en, 0)
            sys.wait(200)
            pcall(gpio.setup, cfg.en, 1)
            sys.wait(800)
        end

        set_status("打开 UVC 摄像头…", C.TEXT)
        opened = excamera.open({
            id            = camera.USB,
            sensor_width  = W,
            sensor_height = H,
            usb_port      = 1,
            save_path     = SAVE_PATH,
        })
        if not opened then
            opened = false
            set_status("打开失败：查 UVC 供电 / UVC_EN(29) / USB 线 / 摄像头", C.DANGER)
            busy = false
            return
        end

        set_status("抓帧中…", C.TEXT)
        local shot_ok = excamera.photo()

        -- 不管成败都释放，避免 USB 一直被占用
        pcall(excamera.close)
        opened = false

        last_size = file_size(SAVE_PATH)
        if not shot_ok or last_size == 0 then
            set_status("抓帧失败（无输出）：确认是 UVC 摄像头、换 USB 线再试", C.DANGER)
            busy = false
            return
        end

        local shown = show_photo()
        set_status(string.format("拍照完成：%d×%d，%d KB，临时文件 %s%s",
            W, H, math.floor(last_size / 1024 + 0.5), SAVE_PATH,
            shown and "" or "（当前固件不能预览 JPEG）"), C.OK)
        busy = false
    end)
end

-- ===== 存到 SD 卡 =====

local function do_save_sd()
    if busy or not page then return end
    if last_size == 0 then
        page.toast("还没有照片，先点「拍照」")
        return
    end

    busy = true
    sys.taskInit(function()
        local name = copy_to_sd()
        busy = false
        if name then
            page.toast("已保存到 " .. name)
            set_status("已保存：" .. name .. string.format("（%d KB）", math.floor(last_size / 1024 + 0.5)), C.OK)
        else
            page.toast("保存失败：没插卡或卡未挂载")
            set_status("保存失败：确认 TF 卡已挂载（/sd）", C.DANGER)
        end
    end)
end

-- ===== 清除 =====

local function do_clear()
    if not page then return end
    if view_img then
        pcall(function() view_img:destroy() end)
        view_img = nil
    end
    if hint_label then
        hint_label:set_text("点下方「拍照」抓一帧")
    end
    last_size = 0
    set_status("已清除。拍照时才给摄像头上电。", C.TEXT_WEAK)
end

-- ===== 生命周期 =====

local function on_create()
    busy, opened, last_size = false, false, 0
    create_ui()
end

local function on_destroy()
    -- 页面关了就别让 USB 摄像头一直开着
    if opened then
        local ok, excamera = pcall(require, "excamera")
        if ok then pcall(excamera.close) end
        opened = false
    end

    if page then
        page.destroy()
        page = nil
    end
    view_card, view_img, hint_label, status_label = nil, nil, nil, nil
    busy = false
    win_id = nil
end

sys.subscribe("OPEN_CAM_WIN", function()
    win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_get_focus  = function() end,
        on_lose_focus = function() end,
    })
end)

sys.subscribe("CAM_SHOT",    function() if page then do_shot() end end)
sys.subscribe("CAM_SAVE_SD", function() if page then do_save_sd() end end)
sys.subscribe("CAM_CLEAR",   do_clear)
