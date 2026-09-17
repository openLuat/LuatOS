--[[
@module  speedtest_win
@summary 网络测速窗口（TabOS 深色玻璃态）
@version 2.0
@date    2026.09.15
@author  江访

消息协议（订阅/发布）:
订阅: OPEN_SPEEDTEST_WIN
订阅: SPDTEST_STARTED / SPDTEST_RESULT({download,upload,ping,jitter}) / SPDTEST_STATUS(msg) / SPDTEST_FINISHED
发布: SPEEDTEST_START / SPEEDTEST_CANCEL
]]

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container = nil

local download_label, upload_label, ping_label, jitter_label, status_label, start_btn
local download_unit_label, upload_unit_label

local sw, sh = 480, 800
local pad = 15
local top_h = 60
local is_compact = false

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    is_compact = (sh > 0 and sh < 340) and (sw > sh)
    pad = is_compact and 6 or theme.page_margin()
    top_h = theme.dp(56)
end

local function format_speed(value)
    if value == nil then return "--" end
    local kbps = value * 1000
    if kbps >= 1000 then
        return string.format("%.1f", kbps / 1000)
    end
    return string.format("%d", math.floor(kbps))
end

local function get_speed_unit(value)
    if value == nil then return "Kbps" end
    if value * 1000 >= 1000 then return "Mbps" end
    return "Kbps"
end

local function format_latency(value)
    if value == nil then return "--" end
    return string.format("%d", math.floor(value))
end

local function reset_display()
    if download_label then download_label:set_text("--") end
    if upload_label then upload_label:set_text("--") end
    if ping_label then ping_label:set_text(is_compact and "--ms" or "--") end
    if jitter_label then jitter_label:set_text(is_compact and "--ms" or "--") end
    if status_label then status_label:set_text("就绪") end
end

--[[构建一张指标卡：标题 + 大数值 + 单位]]
local function build_metric_card(parent, x, y, w, h, title, unit_text, value_color)
    local card = theme.card(parent, { x = x, y = y, w = w, h = h })
    local title_h = theme.dp(theme.F.small + 8)
    local val_h = math.max(theme.dp(30), math.floor(h * 0.42))
    local unit_h = theme.dp(theme.F.small + 8)

    theme.label(card, { x = pad, y = theme.dp(12), w = w - 2 * pad, h = title_h,
        text = title, size = theme.F.small, color = theme.C.t3 })

    local value = theme.label(card, {
        x = pad, y = math.floor((h - val_h) / 2) + theme.dp(4), w = w - 2 * pad, h = val_h,
        text = "--", px_size = math.max(24, math.floor(h * 0.34)), color = value_color,
        align = airui.TEXT_ALIGN_CENTER,
    })
    local unit = theme.label(card, {
        x = pad, y = h - unit_h - theme.dp(10), w = w - 2 * pad, h = unit_h,
        text = unit_text, size = theme.F.small, color = theme.C.t2,
        align = airui.TEXT_ALIGN_CENTER,
    })
    return value, unit
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, screen_w, screen_h)

    -- 标题栏 + 下方指标卡直接挂在背景容器上（各卡高度按屏高算，不依赖滚动）
    titlebar.create(main_container, "网络测速", sw, function()
        if window_id then exwin.close(window_id) end
    end, "延迟 / 抖动 / 下载 / 上传")

    local y = pad + top_h + pad
    local gap = pad
    local cw = math.floor((sw - 2 * pad - gap) / 2)

    local big_h = is_compact and math.floor((screen_h - y - pad) * 0.46)
        or math.min(math.floor((screen_h - y - pad) * 0.42), theme.dp(210))
    if big_h < theme.dp(84) then big_h = theme.dp(84) end

    download_label, download_unit_label = build_metric_card(main_container,
        pad, y, cw, big_h, "下载速度", "Mbps", theme.C.cyan)
    upload_label, upload_unit_label = build_metric_card(main_container,
        pad + cw + gap, y, cw, big_h, "上传速度", "Mbps", theme.C.violet)

    local small_h = is_compact and theme.dp(64) or math.max(theme.dp(80), math.floor(big_h * 0.56))
    local sy = y + big_h + gap
    ping_label = build_metric_card(main_container, pad, sy, cw, small_h, "延迟 (Ping)", "ms", theme.C.t1)
    jitter_label = build_metric_card(main_container, pad + cw + gap, sy, cw, small_h, "抖动 (Jitter)", "ms", theme.C.t1)

    local by = sy + small_h + pad
    local bw = math.floor(sw * 0.5)
    start_btn = theme.button(main_container, {
        x = math.floor((sw - bw) / 2), y = by, w = bw, h = theme.dp(40),
        text = "开始测速", size = theme.F.body, radius = theme.R.md,
        bg = theme.C.amber, fg = theme.C.on_amber,
        on_click = function() sys.publish("SPEEDTEST_START") end,
    })

    status_label = theme.label(main_container, {
        x = 0, y = by + theme.dp(40) + pad, w = sw, h = theme.dp(theme.F.small + 8),
        text = "就绪", size = theme.F.small, color = theme.C.t3,
        align = airui.TEXT_ALIGN_CENTER,
    })
end

local function on_test_started()
    if start_btn then
        start_btn:set_text("测速中...")
        start_btn:set_style({ bg_color = theme.C.stroke, text_color = theme.C.t1 })
    end
    reset_display()
end

local function on_test_result(result)
    local p_suffix = is_compact and "ms" or ""
    if result.ping then
        if ping_label then ping_label:set_text(format_latency(result.ping) .. p_suffix) end
    else
        if ping_label then ping_label:set_text("ERR") end
    end
    if result.jitter then
        if jitter_label then jitter_label:set_text(string.format("%.1f", result.jitter) .. p_suffix) end
    else
        if jitter_label then jitter_label:set_text("ERR") end
    end
    if result.download then
        if download_label then download_label:set_text(format_speed(result.download)) end
        if download_unit_label then download_unit_label:set_text(get_speed_unit(result.download)) end
    else
        if download_label then download_label:set_text("失败") end
        if download_unit_label then download_unit_label:set_text("") end
    end
    if result.upload then
        if upload_label then upload_label:set_text(format_speed(result.upload)) end
        if upload_unit_label then upload_unit_label:set_text(get_speed_unit(result.upload)) end
    else
        if upload_label then upload_label:set_text("失败") end
        if upload_unit_label then upload_unit_label:set_text("") end
    end
end

local function on_status_text(st)
    if status_label then status_label:set_text(st) end
end

local function on_test_finished()
    if start_btn then
        start_btn:set_text("重新测速")
        start_btn:set_style({ bg_color = theme.C.amber, text_color = theme.C.on_amber })
    end
end

local function on_create()
    build_ui()
    sys.subscribe("SPDTEST_STARTED", on_test_started)
    sys.subscribe("SPDTEST_RESULT", on_test_result)
    sys.subscribe("SPDTEST_STATUS", on_status_text)
    sys.subscribe("SPDTEST_FINISHED", on_test_finished)
end

local function on_destroy()
    sys.unsubscribe("SPDTEST_STARTED", on_test_started)
    sys.unsubscribe("SPDTEST_RESULT", on_test_result)
    sys.unsubscribe("SPDTEST_STATUS", on_status_text)
    sys.unsubscribe("SPDTEST_FINISHED", on_test_finished)
    sys.publish("SPEEDTEST_CANCEL")
    if main_container then main_container:destroy(); main_container = nil end
    download_label = nil; upload_label = nil; ping_label = nil; jitter_label = nil
    status_label = nil; start_btn = nil
    download_unit_label = nil; upload_unit_label = nil
    window_id = nil
end

-- 换肤：打脏标记，等本页重新回到前台时重建（换肤当下本页在窗口栈下层，不打扰栈顺序）
local mark_theme_dirty, take_theme_dirty = theme.dirty_flag()
sys.subscribe("UI_THEME_CHANGED", mark_theme_dirty)

local function ongf()
    if take_theme_dirty() then
        local keep_id = window_id
        on_destroy()
        on_create()
        window_id = keep_id
    end
end
local function onlf() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_get_focus = ongf,
        on_lose_focus = onlf,
    })
end

sys.subscribe("OPEN_SPEEDTEST_WIN", open_handler)
