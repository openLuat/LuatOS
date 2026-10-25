--[[
@module  settings_sound_win
@summary 触摸音效子页面（TabOS 深色玻璃态）
@version 2.1
@date    2026.09.15
@author  江访
@usage
订阅: OPEN_SOUND_WIN
发布: BUZZER_GET_ENABLED / BUZZER_GET_DURATION / BUZZER_GET_VOLUME / BUZZER_PLAY_TEST /
      BUZZER_SET_ENABLED / BUZZER_SET_DURATION / BUZZER_SET_VOLUME
订阅: BUZZER_ENABLED_VALUE / BUZZER_ENABLED_CHANGED / BUZZER_DURATION_* / BUZZER_VOLUME_*

v2.1：
  - 时长 / 音量从「[-10] [只读进度条] [+10]」改成可拖动滑块（问题 6），
    直接发 BUZZER_SET_DURATION / BUZZER_SET_VOLUME 绝对值，不再靠 ±10 步进。
  - 开关换成 theme.switch（airui.switch 的选中色被硬编码成蓝色，无法跟随主题）。
]]

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

local window_id = nil
local main_container = nil

local toggle_switch
local duration_slider, duration_label
local volume_slider, volume_label

local sw, sh = 480, 800
local pad = 15

local function update_screen_size()
    sw, sh = screen_w or 480, screen_h or 800
    -- 宽屏有左栏时收窄到右侧内容区（窄屏原样返回）
    sw, sh = theme.content_fit(sw, sh)
    pad = theme.page_margin()
end

--[[构建「可调节滑块」卡片：标题 + 数值 + 滑块 + 测试
   min/max 与业务层 settings_buzz_app.lua 的夹取区间保持一致
   （时长 20~500ms，音量 10~100）。
@return card, 数值 label, 滑块]]
local function build_slider_card(parent, x, y, w, h, title, value_text, min, max, value,
                                 color, set_event)
    local card = theme.card(parent, { x = x, y = y, w = w, h = h })
    local inner = w - 2 * pad

    theme.label(card, { x = pad, y = theme.dp(14), w = math.floor(w * 0.6), h = theme.dp(theme.F.body + 8),
        text = title, size = theme.F.body, color = theme.C.t1 })
    local val = theme.label(card, {
        x = w - pad - theme.dp(110), y = theme.dp(14), w = theme.dp(110),
        h = theme.dp(theme.F.body + 8), text = value_text, size = theme.F.body,
        color = color, align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 滑条高度即滑块直径（lv_slider knob_size = 对象高度），34px 便于手指拖动
    local sl_h = theme.dp(34)
    local sl_y = math.floor(h * 0.42)
    local bar = theme.slider(card, {
        x = pad, y = sl_y, w = inner, h = sl_h,
        min = min, max = max, value = value,
        track = theme.C.track, color = color, knob_color = theme.C.knob,
        on_change = function(self)
            sys.publish(set_event, self:get_value())
        end,
    })

    theme.label(card, {
        x = pad, y = sl_y + sl_h + theme.dp(12), w = theme.dp(120),
        h = theme.dp(theme.F.body + 8), text = "测试", size = theme.F.body,
        color = theme.C.cyan, align = airui.TEXT_ALIGN_LEFT,
        on_click = function() sys.publish("BUZZER_PLAY_TEST") end,
    })

    return card, val, bar
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)
    local _, th = titlebar.create(main_container, "触摸音效", sw,
        function() exwin.close(window_id) end, "触摸反馈音开关、时长与音量")

    local y = pad + th + pad
    local card_w = sw - 2 * pad
    local avail = screen_h - y - pad

    -- 触摸反馈开关行
    local toggle_h = theme.dp(56)
    local toggle_card = theme.card(main_container, { x = pad, y = y, w = card_w, h = toggle_h })
    theme.label(toggle_card, { x = pad, y = 0, w = math.floor(card_w * 0.6), h = toggle_h,
        text = "触摸反馈", size = theme.F.body, color = theme.C.t1 })
    local sw_w = theme.dp(48)
    local sw_h = theme.dp(26)
    toggle_switch = theme.switch(toggle_card, {
        x = card_w - pad - sw_w, y = math.floor((toggle_h - sw_h) / 2),
        w = sw_w, h = sw_h, checked = true,
        color = theme.C.primary,
        on_change = function(handle) sys.publish("BUZZER_SET_ENABLED", handle:get_state()) end,
    })

    -- 两张滑块卡等分剩余空间
    local rest = avail - toggle_h - pad
    local card_h = math.floor((rest - pad) / 2)
    if card_h < theme.dp(96) then card_h = theme.dp(96) end

    local _, dval, dbar = build_slider_card(main_container, pad, y + toggle_h + pad,
        card_w, card_h, "按下发声时长", "50ms", 20, 500, 50,
        theme.C.amber, "BUZZER_SET_DURATION")
    duration_label = dval
    duration_slider = dbar

    local _, vval, vbar = build_slider_card(main_container, pad, y + toggle_h + pad + card_h + pad,
        card_w, card_h, "声音大小", "50", 10, 100, 50,
        theme.C.cyan, "BUZZER_SET_VOLUME")
    volume_label = vval
    volume_slider = vbar
end

local function update_enabled_ui(value)
    if not toggle_switch then return end
    if toggle_switch:get_state() == value then return end
    toggle_switch:set_state(value)
end

local function update_duration_ui(value)
    if duration_label then duration_label:set_text(tostring(value) .. "ms") end
    if duration_slider then duration_slider:set_value(value) end
end

local function update_volume_ui(value)
    if volume_label then volume_label:set_text(tostring(value)) end
    if volume_slider then volume_slider:set_value(value) end
end

local function on_create()
    build_ui()
    sys.publish("BUZZER_GET_ENABLED")
    sys.publish("BUZZER_GET_DURATION")
    sys.publish("BUZZER_GET_VOLUME")
    sys.subscribe("BUZZER_ENABLED_VALUE", update_enabled_ui)
    sys.subscribe("BUZZER_ENABLED_CHANGED", update_enabled_ui)
    sys.subscribe("BUZZER_DURATION_VALUE", update_duration_ui)
    sys.subscribe("BUZZER_DURATION_CHANGED", update_duration_ui)
    sys.subscribe("BUZZER_VOLUME_VALUE", update_volume_ui)
    sys.subscribe("BUZZER_VOLUME_CHANGED", update_volume_ui)
end

local function on_destroy()
    sys.unsubscribe("BUZZER_ENABLED_VALUE", update_enabled_ui)
    sys.unsubscribe("BUZZER_ENABLED_CHANGED", update_enabled_ui)
    sys.unsubscribe("BUZZER_DURATION_VALUE", update_duration_ui)
    sys.unsubscribe("BUZZER_DURATION_CHANGED", update_duration_ui)
    sys.unsubscribe("BUZZER_VOLUME_VALUE", update_volume_ui)
    sys.unsubscribe("BUZZER_VOLUME_CHANGED", update_volume_ui)
    if main_container then main_container:destroy(); main_container = nil end
    toggle_switch = nil
    duration_slider = nil
    duration_label = nil
    volume_slider = nil
    volume_label = nil
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

sys.subscribe("OPEN_SOUND_WIN", open_handler)
