--[[
@module  ui
@summary 基于 lcd 核心库的触屏界面：标题栏 + 状态栏 + 预览画面 + 底部按钮条
@version 1.2
@date    2026.11.18
@usage
    ui.init(info, font_cfg, face_enabled)  初始化（board.lcd_init() 成功后调用）
    ui.set_state(s, msg_key, ...)   切换状态；msg_key 为文案键（见 STR 表），也可直接传字符串
    ui.set_face_status(active, msg_key, ...)  更新人脸状态并锁定或解锁按钮
    ui.set_photo(path, w, h)        设置要显示的照片
    ui.touch(ev, x, y)              触摸事件入口（在主循环里调用）
    ui.tick()                       周期调用：预览时重绘叠加层，其他状态按需重绘
    ui.state() / ui.photo()         查询状态

  两个关键设计（都跟固件能力有关，改代码前先看这里）：

  1) 为什么 UI 用 lcd 核心库而不是 AirUI：
     Air8101 的实时预览是 camera.preview() 硬件直出到屏，画面不经过 LVGL 的 framebuffer；
     AirUI 每次重绘都会把整屏刷成不透明底色，会把摄像头画面盖掉。用 lcd 库 + 部分刷屏
     （lcd.setupBuff + lcd.autoFlush(false) + lcd.flush 只刷脏行），只覆盖标题栏/按钮条，
     中间画面留给摄像头，这是 8101 上"UI 叠加实时预览"唯一稳定的做法。

  2) 为什么文字有 hzfont / ascii 两套：
     V2022_Air8101_104 固件只注册了 ASCII 位图字体 font_opposansm12（没有 *_chinese，
     也没有编入内置 TTF）。所以：
       - 文件系统里有 TTF（默认找 /MiSans_gb2312.ttf）时，用 hzfont 渲染中文，字号可 12~255；
       - 没有 TTF 时自动退回 ASCII 文案 + font_opposansm12，保证任何固件上界面都有字。
     中英文案成对放在 STR 表里，按当前模式取用。
]]

local ui = {}

local W, H = 800, 480

-- RGB888 → RGB565
local function rgb(r, g, b)
    return math.floor(r / 8) * 2048 + math.floor(g / 4) * 32 + math.floor(b / 8)
end

local C = {
    BG        = 0xFFFF,
    HDR_BG    = rgb(26, 42, 66),
    HDR_FG    = 0xFFFF,
    STATUS_BG = rgb(12, 20, 32),
    STATUS_FG = rgb(176, 196, 216),
    HINT      = rgb(110, 122, 138),
    BTN       = rgb(0, 122, 204),
    BTN_DOWN  = rgb(0, 84, 148),
    BTN_OFF   = rgb(104, 112, 124),
    BTN_FG    = 0xFFFF,
    OK        = rgb(0, 180, 90),
    WARN      = rgb(240, 160, 0),
    ERR       = rgb(220, 60, 60),
    LIVE      = rgb(220, 40, 40),
    WHITE     = 0xFFFF,
    BLACK     = 0x0000,
}

local HDR_H, ST_H, FOOT_H = 52, 28, 40
local BTN_H, BTN_GAP, BTN_MARGIN = 32, 8, 12
local IMG_Y = HDR_H + ST_H   -- 图像起始行：与状态栏、按钮条都不重叠

local F_TITLE, F_BODY, F_SMALL, F_BIG = 20, 16, 12, 24   -- hzfont 模式下的字号
local ASCII_SIZE = 12                                    -- ascii 模式只有 12 号位图字体
local ASCII_FONT = nil

local text_mode = "ascii"

-- 文案表：键 → {zh, en}
local STR = {
    title          = { "摄像头预览", "CAMERA PREVIEW" },
    live           = { "实时", "LIVE" },

    btn_preview    = { "开始预览", "PREVIEW" },
    btn_stop       = { "停止预览", "STOP" },
    btn_capture    = { "拍照", "SHOT" },
    btn_save       = { "保存 SD", "SAVE" },
    btn_clear      = { "重置", "RESET" },
    btn_enroll     = { "人脸录入", "ENROLL" },
    btn_verify     = { "人脸验证", "VERIFY" },

    idle_title     = { "摄像头实时预览 + UI 叠加测试", "Live preview + UI overlay test" },
    idle_tip1      = { "点底部「开始预览」启动实时预览", "Tap PREVIEW below to start" },
    idle_tip2      = { "预览时标题栏与按钮条叠加在画面上方", "Header and buttons overlay the video" },

    msg_ready      = { "就绪", "Ready" },
    msg_stopping   = { "正在停止预览…", "Stopping preview..." },
    msg_starting   = { "正在给摄像头上电并开流…", "Powering camera, starting stream..." },
    msg_preview    = { "预览中 %dx%d，点画面可停止", "Live %dx%d, tap to stop" },
    msg_capture    = { "正在拍照（约 2~4 秒）…", "Capturing (2-4s)..." },
    msg_shot_done  = { "拍照完成：%d KB", "Captured: %d KB" },
    msg_saving     = { "正在挂载 TF 卡并写入…", "Mounting TF card, writing..." },
    msg_saved      = { "已保存 %s（%d KB）", "Saved %s (%d KB)" },
    msg_no_photo   = { "还没有照片，先点「拍照」", "No photo yet, tap SHOT" },
    msg_resetting  = { "正在重置…", "Resetting..." },
    msg_stopped    = { "已停止，画面已释放", "Stopped, camera released" },
    msg_retry      = { "摄像头未就绪，自动重试 %d/2", "Camera not ready, retry %d/2" },
    msg_switching  = { "正在切换分辨率…", "Switching resolution..." },
    msg_cam_fail   = { "摄像头连接失败，请按 RESET 重启后再试", "Camera connect failed, press RESET" },
    msg_face_retry = { "摄像头正在恢复，稍后重试", "Camera recovering, try again shortly" },
    msg_face_opening   = { "正在连接人脸模组", "Connecting face module" },
    msg_face_enrolling = { "正在录入，请正对摄像头", "Enrolling, face the camera" },
    msg_face_verifying = { "正在验证，请正对摄像头", "Verifying, face the camera" },
    msg_face_adjust    = { "请正对摄像头，调整距离并移开遮挡", "Face the camera and adjust distance or obstructions" },
    msg_face_enrolled  = { "人脸录入成功（ID %s）", "Enrolled (ID %s)" },
    msg_face_exists    = { "此人已录入，可以直接验证", "Already enrolled, tap VERIFY" },
    msg_face_verified  = { "人脸验证成功（ID %d）", "Verified (ID %d)" },

    err_no_lib     = { "固件未包含 camera / excamera 库", "camera / excamera lib missing" },
    err_cam_init   = { "摄像头初始化失败：查 UVC 供电/线序", "Camera init failed: check UVC power/cable" },
    err_preview    = { "预览启动失败", "Preview start failed" },
    err_capture    = { "抓帧失败：确认是 UVC 摄像头、换 USB 线", "Capture failed: check camera/cable" },
    err_no_photo   = { "还没有照片", "No photo yet" },
    err_no_fatfs   = { "固件未包含 fatfs", "fatfs lib missing" },
    err_sd_mount   = { "TF 卡未挂载：查卡/格式/VBAT_SD", "TF card not mounted: card/format/VBAT_SD" },
    err_read       = { "读取临时照片失败", "Read temp photo failed" },
    err_write      = { "写入 TF 卡失败", "Write TF card failed" },
    err_photo_show = { "照片解码失败", "Photo decode failed" },
    err_face_uart   = { "人脸模组无响应，请检查 UART1 和供电", "Face module timeout, check UART1 and power" },
    err_face_enroll = { "人脸录入失败（%s）", "Enrollment failed (%s)" },
    err_face_verify = { "人脸验证失败（%s）", "Verification failed (%s)" },
    err_face        = { "人脸操作异常，请查看串口日志", "Face operation error, check serial log" },
}

local buttons = {}

local res_label = "RES"      -- 分辨率按钮上显示当前档位，如 960X480

local state        = "boot"
local status_text  = ""
local status_color = C.STATUS_FG
local pressed      = nil
local photo        = nil      -- { path = ..., w = ..., h = ... }
local photo_drawn  = false
local info_text    = ""
local dirty_full   = true
local dirty_overlay = false
local face_busy    = false

-- ============================ 文案 ============================

local function tr(key, ...)
    local e = STR[key]
    local s
    if e then
        s = (text_mode == "hzfont") and e[1] or e[2]
    else
        s = tostring(key)
    end
    if select("#", ...) > 0 then
        s = string.format(s, ...)
    end
    return s
end

-- ============================ 绘制基础 ============================

-- 注意 lcd.fill 的坐标约定：x2 含、y2 不含（底层按行循环 i < y2）
local function fill(x, y, w, h, color)
    lcd.fill(x, y, x + w - 1, y + h, color)
end

-- 当前模式下某个"设计字号"实际使用的像素高度
local function eff(size)
    if text_mode == "hzfont" then return size end
    return ASCII_SIZE
end

-- 取字符串宽度（像素）
local function text_width(str, size)
    local s = eff(size)
    if text_mode == "hzfont" then
        return lcd.getHzFontStrWidth(str, s)
    end
    lcd.setFont(ASCII_FONT)
    return lcd.getStrWidth(str)
end

-- 画一行文字：y 是文字顶部（不是基线）
local function text(x, y, str, fg, bg, size)
    local s = eff(size)
    lcd.setColor(bg, fg)   -- hzfont 用 BACK_COLOR 做抗锯齿边缘混色
    if text_mode == "hzfont" then
        -- hzfont 的 y 是基线，按字号把顶部换算成基线
        lcd.drawHzfontUtf8(x, y + math.floor(s * 0.86), str, s, fg, 1)
    else
        lcd.setFont(ASCII_FONT)
        lcd.drawStr(x, y, str, fg)
    end
end

local function text_center(x, y, w, str, fg, bg, size)
    local tw = text_width(str, size)
    text(x + math.floor((w - tw) / 2), y, str, fg, bg, size)
end

-- ============================ 布局 ============================

local function btn_rect(i)
    local bw = math.floor((W - BTN_MARGIN * 2 - BTN_GAP * (#buttons - 1)) / #buttons)
    local x = BTN_MARGIN + (i - 1) * (bw + BTN_GAP)
    local y = H - FOOT_H + math.floor((FOOT_H - BTN_H) / 2)
    return x, y, bw, BTN_H
end

local function btn_label(id)
    if id == "preview" then
        return tr(state == "preview" and "btn_stop" or "btn_preview")
    elseif id == "res" then
        return res_label
    end
    return tr("btn_" .. id)
end

local function btn_enabled(id)
    if face_busy then return false end
    if id == "preview" then
        return state ~= "capturing" and state ~= "starting"
    elseif id == "capture" then
        return state == "preview" or state == "idle" or state == "error"
    elseif id == "save" then
        return photo ~= nil
    elseif id == "res" then
        return state ~= "starting" and state ~= "capturing"
    elseif id == "clear" then
        return photo ~= nil or state == "preview" or state == "error"
    elseif id == "enroll" or id == "verify" then
        return state == "preview"
    end
    return false
end

local function hit_button(x, y)
    for i, b in ipairs(buttons) do
        local bx, by, bw, bh = btn_rect(i)
        if x >= bx and x < bx + bw and y >= by and y < by + bh then
            return b.id
        end
    end
    return nil
end

-- ============================ 各区域绘制 ============================

local function draw_header()
    fill(0, 0, W, HDR_H, C.HDR_BG)

    local title = tr("title")
    local ty = math.floor((HDR_H - eff(F_TITLE)) / 2)
    text(16, ty, title, C.HDR_FG, C.HDR_BG, F_TITLE)

    if state == "preview" then
        local label = tr("live")
        local s = eff(F_SMALL)
        local tw = text_width(label, F_SMALL)
        local bw, bh = tw + 34, s + 12
        local bx, by = W - 16 - bw, math.floor((HDR_H - bh) / 2)
        fill(bx, by, bw, bh, C.LIVE)
        fill(bx + 8, by + math.floor((bh - 9) / 2), 9, 9, C.WHITE)
        text(bx + 22, by + math.floor((bh - s) / 2), label, C.WHITE, C.LIVE, F_SMALL)
    end
end

local function draw_status()
    fill(0, HDR_H, W, ST_H, C.STATUS_BG)

    local s = eff(F_SMALL)
    local ty = HDR_H + math.floor((ST_H - s) / 2)
    text(14, ty, status_text, status_color, C.STATUS_BG, F_SMALL)

end

local function draw_footer()
    fill(0, H - FOOT_H, W, FOOT_H, C.HDR_BG)
    for i, b in ipairs(buttons) do
        local x, y, w, h = btn_rect(i)
        local on = btn_enabled(b.id)
        local bg = C.BTN_OFF
        if on then
            bg = (pressed == b.id) and C.BTN_DOWN or C.BTN
        end
        fill(x, y, w, h, bg)

        local label = btn_label(b.id)
        local s = eff(F_BODY)
        local ty = y + math.floor((h - s) / 2)
        text_center(x, ty, w, label, C.BTN_FG, bg, F_BODY)
    end
end

local function draw_idle_body()
    local top = HDR_H + ST_H
    local body_h = H - top - FOOT_H
    fill(0, top, W, body_h, C.BG)

    local y = top + 34
    text_center(0, y, W, tr("idle_title"), C.HDR_BG, C.BG, F_BIG)

    y = y + eff(F_BIG) + 18
    text_center(0, y, W, tr("idle_tip1"), C.HINT, C.BG, F_BODY)

    y = y + eff(F_BODY) + 10
    text_center(0, y, W, tr("idle_tip2"), C.HINT, C.BG, F_BODY)

    if info_text ~= "" then
        y = y + eff(F_BODY) + 24
        text_center(0, y, W, info_text, C.HINT, C.BG, F_SMALL)
    end
end

local function draw_photo()
    local p = photo
    if not p then return end

    lcd.clear(C.BLACK)
    local pw, ph = p.w or W, p.h or H
    local px = math.floor((W - pw) / 2)
    local py = math.floor((H - ph) / 2)
    if px < 0 then px = 0 end
    if py < 0 then py = 0 end

    local ok = lcd.showImage(px, py, p.path)
    if not ok then
        local cy = math.floor(H / 2)
        text_center(0, cy - 26, W, tr("err_photo_show"), C.ERR, C.BLACK, F_BODY)
    end
end

-- ============================ 对外接口 ============================

--[[
初始化界面。
@api ui.init(info, font_cfg, face_enabled)
@string info 首页显示的一行硬件信息（建议纯 ASCII）
@table font_cfg 字体配置 { paths = {...}, cache = 512 }，为 nil 时直接用 ASCII 位图字体
@boolean face_enabled 是否显示人脸录入和验证按钮
]]
function ui.init(info, font_cfg, face_enabled)
    W, H = lcd.getSize()
    info_text = info or ""
    ASCII_FONT = lcd.font_opposansm12
    buttons = {
        { id = "preview" },
        { id = "capture" },
        { id = "save" },
        { id = "res" },
        { id = "clear" },
    }
    if face_enabled then
        buttons[#buttons + 1] = { id = "enroll" }
        buttons[#buttons + 1] = { id = "verify" }
    end
    face_busy = false

    -- 先尝试外部 TTF：本固件没有内置字库，也没有中文位图字体
    text_mode = "ascii"
    font_cfg = font_cfg or {}
    if hzfont and lcd.drawHzfontUtf8 then
        for _, path in ipairs(font_cfg.paths or {}) do
            if io.exists and io.exists(path) then
                local ok = hzfont.init(path, font_cfg.cache or 512, false)
                log.info("ui", "hzfont.init", path, ok)
                if ok then
                    text_mode = "hzfont"
                    break
                end
            end
        end
    end
    if text_mode == "ascii" and not ASCII_FONT then
        log.error("ui", "固件既没有 hzfont 字库也没有 font_opposansm12，界面文字无法显示")
    end
    log.info("ui", "文字模式:", text_mode)

    state = "idle"
    status_text = tr("msg_ready")
    status_color = C.STATUS_FG
    dirty_full = true
end

function ui.state()
    return state
end

-- 当前文字模式："hzfont"（加载到 TTF，可显示中文/大字）或 "ascii"（只能英文 12 号）
function ui.text_mode()
    return text_mode
end

--[[
切换状态。msg_key 取 STR 里的键；键不存在时按普通字符串显示。
@api ui.set_state(s, msg_key, ...)
@string s boot / idle / starting / preview / capturing / photo / error
]]
--[[
设置分辨率按钮上显示的文字（如 "960X480"）。
@api ui.set_res_label(text)
]]
function ui.set_res_label(text)
    if text and text ~= "" and text ~= res_label then
        res_label = text
        dirty_full = true
    end
end

function ui.set_state(s, msg_key, ...)
    state = s
    if msg_key then
        status_text = tr(msg_key, ...)
    end
    if s == "error" then
        status_color = C.ERR
    elseif s == "preview" or s == "photo" then
        status_color = C.OK
    elseif s == "starting" or s == "capturing" or s == "saving" then
        status_color = C.WARN
    else
        status_color = C.STATUS_FG
    end
    dirty_full = true
end

function ui.set_face_status(active, msg_key, ...)
    face_busy = active
    status_text = tr(msg_key, ...)
    status_color = active and C.WARN or C.STATUS_FG
    dirty_overlay = true
end

--[[
设置要显示的照片。宽高不传则按整屏居中处理。
@api ui.set_photo(path, w, h)
]]
function ui.set_photo(path, w, h)
    photo = { path = path, w = w, h = h }
    photo_drawn = false
    dirty_full = true
end

function ui.clear_photo()
    photo = nil
    photo_drawn = false
    dirty_full = true
end

--[[
绘制一帧并刷屏。
@api ui.render(full)
@boolean full true 表示整页重绘；false 只重绘标题栏/状态栏/按钮条（预览叠加用）
]]
function ui.render(full)
    if state == "photo" then
        if full or not photo_drawn then
            draw_photo()
            photo_drawn = true
        end
        draw_header()
        draw_status()
        draw_footer()
    elseif state == "preview" then
        -- 进入预览的那一帧先清黑，之后由 ui.draw_frame() 逐帧画画面 + 叠加层
        if full then
            lcd.clear(C.BLACK)
        end
        draw_header()
        draw_status()
        draw_footer()
    else
        if full then
            lcd.clear(C.BG)
            draw_idle_body()
        end
        draw_header()
        draw_status()
        draw_footer()
    end
    lcd.flush()
    dirty_full, dirty_overlay = false, false
end

--[[
周期调用：预览状态持续重绘叠加层（压住摄像头画面），其他状态只在需要时重绘。
@api ui.tick()
]]
function ui.tick()
    -- 人脸操作只更新叠加层，保留当前预览帧。
    if dirty_full or dirty_overlay then
        ui.render(dirty_full)
    end
end

--[[
画一帧预览画面：JPEG 解码 → 居中贴上屏 → 叠标题栏/按钮条 → 刷屏。
必须用 image2raw + lcd.draw，不能用 lcd.showImage（1024 宽屏上会出竖条纹）。
@api ui.draw_frame(path)
@string path 预览帧文件路径
@return boolean 成功返回 true
]]
local frame_fail = 0

function ui.draw_frame(path)
    local raw = lcd.image2raw(path)
    if not raw then
        frame_fail = frame_fail + 1
        if frame_fail % 20 == 1 then
            log.warn("ui", "预览帧解码失败", frame_fail)
        end
        return false
    end
    frame_fail = 0
    local pw = raw.width or 0
    local ph = raw.height or 0
    if pw == 0 or ph == 0 then
        raw:free()
        return false
    end

    local body_h = H - IMG_Y - FOOT_H
    local px = (W - pw) // 2
    local py = IMG_Y - math.max(0, (ph - body_h) // 2)

    -- RGB 驱动按照源图行宽裁剪超屏部分，提交前恢复被图像覆盖的界面栏。
    local drawn = lcd.draw(px, py, 0, 0, raw)
    raw:free()
    if not drawn then return false end
    if py < IMG_Y then
        draw_header()
        draw_status()
    end
    if py + ph > H - FOOT_H then
        draw_footer()
    end
    lcd.flush()
    return true
end

--[[
触摸事件入口（在主循环里调用，不要在 tp 回调里直接调用）。
@api ui.touch(ev, x, y)
]]
function ui.touch(ev, x, y)
    if not tp then return end
    if ev == tp.EVENT_DOWN then
        local id = hit_button(x, y)
        if id and btn_enabled(id) then
            pressed = id
            ui.render(state ~= "preview" and dirty_full)
        end
    elseif ev == tp.EVENT_UP then
        local id = pressed
        pressed = nil
        if id then
            ui.render(state ~= "preview" and dirty_full)
            if hit_button(x, y) == id and btn_enabled(id) then
                sys.publish("CAM_UI_ACTION", id)
            end
        elseif not face_busy and state == "preview" and y > HDR_H + ST_H and y < H - FOOT_H then
            -- 点画面 = 停止预览。这条兜底很重要：万一硬件预览层盖住了叠加层，
            -- 用户仍然有办法退出预览回到界面，不会卡在摄像头画面里。
            sys.publish("CAM_UI_ACTION", "preview")
        end
    end
end

return ui
