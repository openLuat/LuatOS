--[[
@module  ui_air
@summary 空气质量页：AirVOC_1000（AGS02MA）TVOC 实时值 + 等级 + 接线排查
@version 2.0
@date    2026.10.16
@usage
    sys.publish("OPEN_AIR_WIN")

说明
1. 数据来自 app_voc（周期采集，默认 5 秒一次），页面订阅 VOC_UPDATE 增量刷新；
2. "立即读取"手动触发一次；"重新探测"重新读地址（换线/换模块后用）；
3. 器件接在 I2C 排针上（SCL=GPIO38 / SDA=GPIO39，与 GT911 触摸、SHT30 同一条总线），
   地址 0x1A；AGS02MA 上电需要预热，前一两分钟数值漂移属正常。

布局约定（v2.0 多屏等比缩放，与 ui_sensor 保持一致）
1. 页面坐标一律用**设计坐标**（设计基准 800×480）：算布局用 ui_theme.SCREEN.DW / DH，
   不要用 S.W / S.H（那是真实分辨率，1024×600 屏上会错位）；
   ui_kit 组件内部会把设计坐标 × SCALE 换算成实际像素；
2. 正文可用高度 = DH - TITLE_H = 424 设计像素（标题栏下方），本页所有内容都落在 424 以内。
]]

local exwin      = require "exwin"
local ui         = require "ui_kit"
local T          = require "ui_theme"
local app_voc    = require "app_voc"
local app_devsel = require "app_devsel"

local C, F, S, G = T.COLOR, T.FONT, T.SCREEN, T.GAP

-- ===== 设计坐标布局（基准 800×480，全部用 S.DW / S.DH 推导） =====
local PAD    = G.M                                    -- 页面左右留白
local BODY_W = S.DW - PAD * 2                         -- 内容总宽
local CARD_W = math.floor((S.DW - PAD * 3) / 2)       -- 并排两卡宽度
local CARD_H = 164
local ROW_Y  = PAD - 4                                -- 数值卡顶部
local INFO_Y = ROW_Y + CARD_H + PAD - 8               -- 信息卡顶部
local INFO_H = 120
local BTN_Y  = INFO_Y + INFO_H + G.XS                 -- 按钮行
local BTN_H  = 52
local BTN_W  = math.floor((S.DW - PAD * 4) / 3)
local CELL_W = 240                                    -- 信息卡每栏宽度
local NOTE_Y = BTN_Y + BTN_H + G.XS                   -- 接线说明

local win_id, page
local ppb_label, ppm_label, level_label, time_label, status_label

-- 等级配色：1 优 / 2 良好 / 3 轻度污染 / 4 中度污染 / 5 重度污染
local function level_color(level)
    if level == 1 then return C.OK end
    if level == 2 then return C.PRIMARY_LIGHT end
    if level == 3 then return C.WARN end
    return C.DANGER
end

local function value_card(x, title, value_color, value_size, unit)
    local card = ui.card({ parent = page.body, x = x, y = ROW_Y, w = CARD_W, h = CARD_H })
    ui.label({
        parent = card, x = 0, y = 18, w = CARD_W, h = 22,
        text = title, size = F.SMALL, color = C.TEXT_SUB, align = airui.TEXT_ALIGN_CENTER,
    })
    local value = ui.label({
        parent = card, x = 0, y = 54, w = CARD_W, h = 62,
        text = "--", size = value_size, color = value_color,
        align = airui.TEXT_ALIGN_CENTER,
    })
    local sub = ui.label({
        parent = card, x = 0, y = 122, w = CARD_W, h = 22,
        text = unit, size = F.SMALL, color = C.TEXT_WEAK, align = airui.TEXT_ALIGN_CENTER,
    })
    return value, sub
end

local function info_cell(parent, x, title, text)
    ui.label({
        parent = parent, x = x, y = 14, w = CELL_W, h = 22,
        text = title, size = F.SMALL, color = C.TEXT_SUB,
    })
    return ui.label({
        parent = parent, x = x, y = 38, w = CELL_W, h = 28,
        text = text or "--", size = F.NORMAL, color = C.TEXT,
    })
end

local function refresh()
    if not (page and ppb_label) then return end

    -- 本页未启用（现场一次只接一块配件板）：说明清楚，别让人以为传感器坏了
    if not app_devsel.is_active("voc") then
        ppb_label:set_text("--")
        level_label:set_text("--")
        ppm_label:set_text("--")
        time_label:set_text("--:--:--")
        status_label:set_text("本页未启用（当前启用的是「" .. app_devsel.name()
            .. "」）· 点下方「改用空气质量」切换后自动重启")
        return
    end

    local d = app_voc.get()
    if d then
        ppb_label:set_text(tostring(d.ppb))
        level_label:set_text(string.format("%d %s", d.level, d.desc or ""))
        -- 等级配色：airui 若没有 set_color 就保持原色，不能因为配色把刷新打断
        pcall(function() level_label:set_color(level_color(d.level)) end)
        ppm_label:set_text(string.format("折算 %.3f ppm", d.ppm))
        time_label:set_text(d.ts and os.date("%H:%M:%S", d.ts) or "--:--:--")
    else
        ppb_label:set_text("--")
        level_label:set_text("--")
        ppm_label:set_text("尚未采到数据")
        time_label:set_text("--:--:--")
    end

    local st = app_voc.status()
    if st == "ok" then
        status_label:set_text(string.format("采集正常，每 %.0f 秒自动更新一次",
            app_voc.interval() / 1000))
    elseif st == "init" then
        status_label:set_text("等待首次采集…")
    else
        status_label:set_text("传感器不可用（" .. tostring(st)
            .. "）：查 3V3 / GND / SCL / SDA 接线；AGS02MA 要预热 ≥2 分钟，程序会自动重试")
    end
end

local function create_ui()
    page = ui.page({
        title = "空气质量",
        on_back = function() if win_id then exwin.close(win_id) end end,
    })

    -- ===== TVOC 数值卡（大数字 + ppb 单位） =====
    ppb_label = value_card(PAD, "TVOC", C.PRIMARY, F.HUGE, "ppb")

    -- ===== 等级卡（等级文字用等级色，底部小字放折算 ppm） =====
    level_label, ppm_label = value_card(PAD * 2 + CARD_W, "空气质量等级", C.OK, F.BIG, "")

    -- ===== 信息卡：从机地址 + 更新时间 + 状态行 =====
    local info_card = ui.card({ parent = page.body, x = PAD, y = INFO_Y, w = BODY_W, h = INFO_H })
    info_cell(info_card, PAD, "从机地址", "0x1A（AGS02MA）")
    time_label = info_cell(info_card, PAD + CELL_W, "更新时间")
    ui.card({
        parent = info_card, x = PAD, y = 72, w = BODY_W - PAD * 2, h = 1,
        color = C.BORDER, radius = 0,
    })
    status_label = ui.label({
        parent = info_card, x = PAD, y = 80, w = BODY_W - PAD * 2, h = 30,
        text = "", size = F.TINY, color = C.TEXT_WEAK,
    })

    -- ===== 操作按钮：立即读取 / 重新探测 / 改用 XX =====
    ui.button({
        parent = page.body, x = PAD, y = BTN_Y, w = BTN_W, h = BTN_H, text = "立即读取",
        on_click = function()
            sys.taskInit(function()
                page.toast("正在读取…")
                app_voc.read_once()
                refresh()
            end)
        end,
    })
    ui.button({
        parent = page.body, x = PAD * 2 + BTN_W, y = BTN_Y, w = BTN_W, h = BTN_H,
        text = "重新探测",
        color = C.PRIMARY_SOFT, text_color = C.PRIMARY,
        on_click = function()
            sys.taskInit(function()
                page.toast("正在重新探测 0x1A…")
                local ok = app_voc.retry()
                refresh()
                page.toast(ok and "已找到空气质量传感器" or "未找到，检查接线")
            end)
        end,
    })

    -- 切换配件板：写 fskv + 重启；只有一个可选配件板时不显示该按钮（other 返回 nil）
    local other_id, other_name = app_devsel.other()
    if other_id then
        ui.button({
            parent = page.body, x = PAD * 3 + BTN_W * 2, y = BTN_Y, w = BTN_W, h = BTN_H,
            text = "改用" .. other_name,
            color = C.WARN,
            on_click = function()
                page.toast("切换为「" .. other_name .. "」并重启…")
                app_devsel.set(other_id)
            end,
        })
    end

    -- ===== 接线说明（弱化小字） =====
    ui.label({
        parent = page.body, x = PAD, y = NOTE_Y, w = BODY_W, h = 44,
        text = "接线：VDD / GND / SCL / SDA 接板上 I2C 排针（SCL=GPIO38、SDA=GPIO39，与触摸同总线）。\n"
            .. "AGS02MA 要求 I2C ≤30kHz（比触摸苛刻），空气质量模式整条总线已自动降速；"
            .. "上电需预热一两分钟。",
        size = F.TINY, color = C.TEXT_WEAK,
    })
end

local function on_create()
    create_ui()
    refresh()
    sys.subscribe("VOC_UPDATE", refresh)
    sys.subscribe("VOC_ERROR", refresh)
end

local function on_destroy()
    sys.unsubscribe("VOC_UPDATE", refresh)
    sys.unsubscribe("VOC_ERROR", refresh)
    if page then
        page.destroy()
        page = nil
    end
    ppb_label, ppm_label, level_label, time_label, status_label = nil, nil, nil, nil, nil
    win_id = nil
end

sys.subscribe("OPEN_AIR_WIN", function()
    win_id = exwin.open({
        on_create     = on_create,
        on_destroy    = on_destroy,
        on_get_focus  = refresh,
        on_lose_focus = function() end,
    })
end)
