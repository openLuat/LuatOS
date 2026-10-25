--[[
@module  settings_display_win
@summary 亮度与声音子页面（TabOS 深色玻璃态）
@version 2.2
@date    2026.09.23
@author  江访
@usage
订阅: OPEN_DISPLAY_WIN
发布: DISPLAY_BRIGHTNESS_GET / DISPLAY_BRIGHTNESS_SET(level) /
      AUDIO_VOLUME_GET / AUDIO_VOLUME_SET(level) / AUDIO_PLAY_TEST
订阅: DISPLAY_BRIGHTNESS_CHANGED / DISPLAY_BRIGHTNESS_VALUE /
      AUDIO_VOLUME_CHANGED / AUDIO_VOLUME_VALUE

v2.1：把原来的「[-10] [只读进度条] [+10]」三个控件合并成一条可拖动滑块
     （问题：亮度调节改成滑块）。轨道/滑块/进度三色全部走主题令牌。
v2.2：并入媒体音量调节（hw.audio 存在时默认启用，无需配置开关），
     标题「显示亮度」→「亮度和声音」；无音频硬件时仍只显示亮度卡。
]]

local theme = require "ui_theme"
local titlebar = require "settings_titlebar"

-- 支持 audio 功能（hw.audio 已配置）即默认开启音量调节
local has_audio = (_G.project_config and _G.project_config.hw and _G.project_config.hw.audio) ~= nil

local window_id = nil
local main_container = nil
local brightness_bar, brightness_label
local volume_bar, volume_label

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

local function update_volume_ui(value)
    if volume_bar then volume_bar:set_value(value) end
    if volume_label then volume_label:set_text(tostring(value) .. "%") end
end

--[[构建「滑块调节」卡片：标题 + 数值 + 可拖滑块 + 底部行。
底部行两种形态：footer_hint 灰色提示文字；footer_test 非 nil 时显示可点「测试」。
min/max 与业务层 settings_display_app.lua 的夹取区间保持一致
（亮度 10~100，媒体音量 0~100）。
@return 数值 label, 滑块]]
local function build_slider_card(parent, x, y, w, h, title, value_text, min, max, value,
                                color, on_change, footer_hint, footer_test)
    local card = theme.card(parent, { x = x, y = y, w = w, h = h })
    local inner_w = w - 2 * pad

    theme.label(card, { x = pad, y = theme.dp(14), w = math.floor(w * 0.6), h = theme.dp(theme.F.body + 8),
        text = title, size = theme.F.body, color = theme.C.t1 })
    local val = theme.label(card, {
        x = w - pad - theme.dp(90), y = theme.dp(14), w = theme.dp(90),
        h = theme.dp(theme.F.body + 8), text = value_text, size = theme.F.body,
        color = color, align = airui.TEXT_ALIGN_RIGHT,
    })

    --[[滑块：拖动即时生效。
    滑条高度即滑块直径（lv_slider 的 knob_size = 对象高度），30px 保证手指好拖。]]
    local sl_h = theme.dp(30)
    local sl_y = math.floor(h * 0.42)
    local bar = theme.slider(card, {
        x = pad, y = sl_y, w = inner_w, h = sl_h,
        min = min, max = max, value = value,
        track = theme.C.track, color = color, knob_color = theme.C.knob,
        on_change = on_change,
    })

    local ft_y = sl_y + sl_h + theme.dp(10)
    local ft_h = theme.dp(theme.F.tiny + 8)
    if footer_test then
        theme.label(card, {
            x = pad, y = ft_y, w = theme.dp(120), h = theme.dp(theme.F.body + 8),
            text = footer_test, size = theme.F.body,
            color = theme.C.cyan, align = airui.TEXT_ALIGN_LEFT,
            on_click = function() sys.publish("AUDIO_PLAY_TEST") end,
        })
    elseif footer_hint then
        theme.label(card, {
            x = pad, y = ft_y, w = inner_w, h = ft_h,
            text = footer_hint, size = theme.F.tiny, color = theme.C.t3,
        })
    end

    return val, bar
end

local function build_ui()
    update_screen_size()
    main_container = theme.page_bg(airui.screen, sw, sh)
    local _, th = titlebar.create(main_container, "亮度和声音", sw,
        function() exwin.close(window_id) end, "屏幕背光与媒体音量调节")

    local y = pad + th + pad
    local card_w = sw - 2 * pad
    local avail = screen_h - y - pad

    -- 有音频硬件：亮度/音量两张卡等分；否则只留亮度卡（原布局）
    local card_h
    if has_audio then
        card_h = math.floor((avail - pad) / 2)
        if card_h < theme.dp(110) then card_h = theme.dp(110) end
    else
        card_h = math.min(theme.dp(150), math.max(theme.dp(110), math.floor(avail * 0.45)))
    end

    brightness_label, brightness_bar = build_slider_card(main_container, pad, y,
        card_w, card_h, "屏幕亮度", "50%", 10, 100, 50, theme.C.amber,
        function(self)
            local v = self:get_value()
            if brightness_label then brightness_label:set_text(tostring(v) .. "%") end
            sys.publish("DISPLAY_BRIGHTNESS_SET", v)
        end,
        "拖动滑块调节，松手立即生效（PWM 背光）")

    if has_audio then
        volume_label, volume_bar = build_slider_card(main_container, pad, y + card_h + pad,
            card_w, card_h, "媒体音量", "70%", 0, 100, 70, theme.C.cyan,
            function(self)
                local v = self:get_value()
                if volume_label then volume_label:set_text(tostring(v) .. "%") end
                sys.publish("AUDIO_VOLUME_SET", v)
            end,
            nil, "测试")
    end
end

local function on_create()
    build_ui()
    sys.publish("DISPLAY_BRIGHTNESS_GET")
    sys.subscribe("DISPLAY_BRIGHTNESS_CHANGED", update_brightness_ui)
    sys.subscribe("DISPLAY_BRIGHTNESS_VALUE", update_brightness_ui)
    if has_audio then
        sys.publish("AUDIO_VOLUME_GET")
        sys.subscribe("AUDIO_VOLUME_CHANGED", update_volume_ui)
        sys.subscribe("AUDIO_VOLUME_VALUE", update_volume_ui)
    end
end

local function on_destroy()
    sys.unsubscribe("DISPLAY_BRIGHTNESS_CHANGED", update_brightness_ui)
    sys.unsubscribe("DISPLAY_BRIGHTNESS_VALUE", update_brightness_ui)
    if has_audio then
        sys.unsubscribe("AUDIO_VOLUME_CHANGED", update_volume_ui)
        sys.unsubscribe("AUDIO_VOLUME_VALUE", update_volume_ui)
    end
    if main_container then main_container:destroy(); main_container = nil end
    brightness_bar = nil
    brightness_label = nil
    volume_bar = nil
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

sys.subscribe("OPEN_DISPLAY_WIN", open_handler)
