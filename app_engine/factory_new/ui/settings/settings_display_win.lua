--[[
@module  settings_display_win
@summary 显示与亮度子页面（TabOS 深色玻璃态）
@version 2.1
@date    2026.09.15
@author  江访
@usage
订阅: OPEN_DISPLAY_WIN
发布: DISPLAY_BRIGHTNESS_GET / DISPLAY_BRIGHTNESS_SET(level)
订阅: DISPLAY_BRIGHTNESS_CHANGED / DISPLAY_BRIGHTNESS_VALUE

v2.1：把原来的「[-10] [只读进度条] [+10]」三个控件合并成一条可拖动滑块
     （问题：亮度调节改成滑块）。轨道/滑块/进度三色全部走主题令牌。
]]

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container = nil
local brightness_bar, brightness_label

local sw, sh = 480, 800
local pad = 15

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

local function update_brightness_ui(value)
    if brightness_bar then brightness_bar:set_value(value) end
    if brightness_label then brightness_label:set_text(tostring(value) .. "%") end
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)
    local _, th = titlebar.create(main_container, "显示亮度", sw,
        function() exwin.close(window_id) end, "屏幕背光强度调节")

    local y = pad + th + pad
    local card_h = math.min(theme.dp(150), math.max(theme.dp(110), math.floor((screen_h - y - pad) * 0.45)))
    local card_w = sw - 2 * pad
    local card = theme.card(main_container, { x = pad, y = y, w = card_w, h = card_h })

    local inner_w = card_w - 2 * pad

    theme.label(card, { x = pad, y = theme.dp(14), w = math.floor(card_w * 0.6), h = theme.dp(theme.F.body + 8),
        text = "屏幕亮度", size = theme.F.body, color = theme.C.t1 })
    brightness_label = theme.label(card, {
        x = card_w - pad - theme.dp(90), y = theme.dp(14), w = theme.dp(90),
        h = theme.dp(theme.F.body + 8), text = "50%", size = theme.F.body,
        color = theme.C.amber, align = airui.TEXT_ALIGN_RIGHT,
    })

    --[[亮度滑块：拖动即时生效。
    原来左右两个 [-10]/[+10] 幽灵按钮 + 一条只读进度条，现在合并成一条可拖滑块 ——
    少两次点击，且能直接看到自己拖到了哪一档。
    滑条高度即滑块直径（lv_slider 的 knob_size = 对象高度），30px 保证手指好拖。
    取值 10~100 与业务层 settings_display_app.lua 的夹取区间一致，避免左侧死区。]]
    local sl_h = theme.dp(30)
    local sl_y = math.floor(card_h * 0.42)
    brightness_bar = theme.slider(card, {
        x = pad, y = sl_y, w = inner_w, h = sl_h,
        min = 10, max = 100, value = 50,
        track = theme.C.track, color = theme.C.amber, knob_color = theme.C.knob,
        on_change = function(self)
            local v = self:get_value()
            if brightness_label then brightness_label:set_text(tostring(v) .. "%") end
            sys.publish("DISPLAY_BRIGHTNESS_SET", v)
        end,
    })

    theme.label(card, {
        x = pad, y = sl_y + sl_h + theme.dp(10), w = inner_w, h = theme.dp(theme.F.tiny + 8),
        text = "拖动滑块调节，松手立即生效（PWM 背光）", size = theme.F.tiny, color = theme.C.t3,
    })
end

local function on_create()
    build_ui()
    sys.publish("DISPLAY_BRIGHTNESS_GET")
    sys.subscribe("DISPLAY_BRIGHTNESS_CHANGED", update_brightness_ui)
    sys.subscribe("DISPLAY_BRIGHTNESS_VALUE", update_brightness_ui)
end

local function on_destroy()
    sys.unsubscribe("DISPLAY_BRIGHTNESS_CHANGED", update_brightness_ui)
    sys.unsubscribe("DISPLAY_BRIGHTNESS_VALUE", update_brightness_ui)
    if main_container then main_container:destroy(); main_container = nil end
    brightness_bar = nil
    brightness_label = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    window_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_DISPLAY_WIN", open_handler)
