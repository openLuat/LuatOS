--[[
@module  settings_sound_win
@summary 声音与触摸子页面
@version 1.0
@date    2026.04.24
@author  江访
]]

local window_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 15
local card_w = 460

local toggle_switch
local duration_slider, duration_label
local volume_slider, volume_label

local COLOR_PRIMARY        = 0x007AFF
local COLOR_ACCENT         = 0xFF9800
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

local function update_screen_size()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        screen_w, screen_h = phys_w, phys_h
    else
        screen_w, screen_h = phys_h, phys_w
    end
    margin = math.floor(screen_w * 0.03)
    card_w = screen_w - 2 * margin
end

local function build_ui()
    update_screen_size()
    local btn_w = math.floor(50 * _G.density_scale)
    local btn_margin = math.floor(20 * _G.density_scale)
    local bar_x = btn_margin + btn_w + math.floor(10 * _G.density_scale)
    local bar_w = card_w - 2 * btn_margin - 2 * btn_w - math.floor(20 * _G.density_scale)
    main_container = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = screen_w,
        h = screen_h,
        color = COLOR_BG
    })

    local tb = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = screen_w,
        h = math.floor(60 * _G.density_scale),
        color = COLOR_PRIMARY
    })
    local bb = airui.container({
        parent = tb,
        x = 10,
        y = 10,
        w = math.floor(50 * _G.density_scale),
        h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(window_id) end
    })
    airui.label({
        parent = bb,
        x = 0,
        y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = tb,
        x = math.floor(60 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale),
        h = math.floor(40 * _G.density_scale),
        text = "触摸音效",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local th = math.floor(60 * _G.density_scale)
    local ct = airui.container({
        parent = main_container,
        x = 0,
        y = th,
        w = screen_w,
        h = screen_h - th,
        color = COLOR_BG
    })

    local toggle_card = airui.container({
        parent = ct,
        x = margin,
        y = math.floor(20 * _G.density_scale),
        w = card_w,
        h = math.floor(70 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    airui.label({
        parent = toggle_card,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(20 * _G.density_scale),
        w = math.floor(200 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "触摸反馈",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    toggle_switch = airui.switch({
        parent = toggle_card,
        x = card_w - math.floor(80 * _G.density_scale),
        y = math.floor(15 * _G.density_scale),
        w = math.floor(60 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        checked = true,
        on_change = function(self)
            sys.publish("BUZZER_SET_ENABLED", self:get_state())
        end
    })

    local duration_card = airui.container({
        parent = ct,
        x = margin,
        y = math.floor(110 * _G.density_scale),
        w = card_w,
        h = math.floor(140 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    airui.label({
        parent = duration_card,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "按下发声时长",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    duration_label = airui.label({
        parent = duration_card,
        x = card_w - math.floor(120 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(100 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "50ms",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.button({
        parent = duration_card,
        x = btn_margin,
        y = math.floor(55 * _G.density_scale),
        w = btn_w,
        h = math.floor(40 * _G.density_scale),
        text = "-10",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_ACCENT,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function() sys.publish("BUZZER_DURATION_DECREASE") end
    })
    duration_slider = airui.bar({
        parent = duration_card,
        x = bar_x,
        y = math.floor(65 * _G.density_scale),
        w = bar_w,
        h = math.floor(25 * _G.density_scale),
        min = 20,
        max = 500,
        value = 50,
        indicator_color = COLOR_ACCENT,
        bg_color = COLOR_DIVIDER
    })
    airui.button({
        parent = duration_card,
        x = card_w - btn_margin - btn_w,
        y = math.floor(55 * _G.density_scale),
        w = btn_w,
        h = math.floor(40 * _G.density_scale),
        text = "+10",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_ACCENT,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function() sys.publish("BUZZER_DURATION_INCREASE") end
    })
    airui.label({
        parent = duration_card,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(110 * _G.density_scale),
        w = math.floor(80 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        text = "测试",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = function()
            sys.publish("BUZZER_PLAY_TEST")
        end
    })

    local volume_card = airui.container({
        parent = ct,
        x = margin,
        y = math.floor(270 * _G.density_scale),
        w = card_w,
        h = math.floor(140 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    airui.label({
        parent = volume_card,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "声音大小",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    volume_label = airui.label({
        parent = volume_card,
        x = card_w - math.floor(120 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(100 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "50",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.button({
        parent = volume_card,
        x = btn_margin,
        y = math.floor(55 * _G.density_scale),
        w = btn_w,
        h = math.floor(40 * _G.density_scale),
        text = "-10",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_ACCENT,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function() sys.publish("BUZZER_VOLUME_DECREASE") end
    })
    volume_slider = airui.bar({
        parent = volume_card,
        x = bar_x,
        y = math.floor(65 * _G.density_scale),
        w = bar_w,
        h = math.floor(25 * _G.density_scale),
        min = 10,
        max = 100,
        value = 50,
        indicator_color = COLOR_ACCENT,
        bg_color = COLOR_DIVIDER
    })
    airui.button({
        parent = volume_card,
        x = card_w - btn_margin - btn_w,
        y = math.floor(55 * _G.density_scale),
        w = btn_w,
        h = math.floor(40 * _G.density_scale),
        text = "+10",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_ACCENT,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function() sys.publish("BUZZER_VOLUME_INCREASE") end
    })
    airui.label({
        parent = volume_card,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(110 * _G.density_scale),
        w = math.floor(80 * _G.density_scale),
        h = math.floor(25 * _G.density_scale),
        text = "测试",
        font_size = math.floor(20 * _G.density_scale),
        color = COLOR_PRIMARY,
        align = airui.TEXT_ALIGN_LEFT,
        on_click = function()
            sys.publish("BUZZER_PLAY_TEST")
        end
    })
end

local function update_enabled_ui(value)
    if not toggle_switch then return end
    if toggle_switch:get_state() == value then return end
    toggle_switch:set_state(value)
end

local function update_enabled_ui_alias(value) update_enabled_ui(value) end

local function update_duration_ui(value)
    if duration_label then
        duration_label:set_text(tostring(value) .. "ms")
    end
    if duration_slider then
        duration_slider:set_value(value)
    end
end

local function update_volume_ui(value)
    if volume_label then
        volume_label:set_text(tostring(value))
    end
    if volume_slider then
        volume_slider:set_value(value)
    end
end

local function on_create()
    build_ui()
    sys.publish("BUZZER_GET_ENABLED")
    sys.publish("BUZZER_GET_DURATION")
    sys.publish("BUZZER_GET_VOLUME")
    sys.subscribe("BUZZER_ENABLED_VALUE", update_enabled_ui_alias)
    sys.subscribe("BUZZER_ENABLED_CHANGED", update_enabled_ui)
    sys.subscribe("BUZZER_DURATION_VALUE", update_duration_ui)
    sys.subscribe("BUZZER_DURATION_CHANGED", update_duration_ui)
    sys.subscribe("BUZZER_VOLUME_VALUE", update_volume_ui)
    sys.subscribe("BUZZER_VOLUME_CHANGED", update_volume_ui)
end

local function on_destroy()
    sys.unsubscribe("BUZZER_ENABLED_VALUE", update_enabled_ui_alias)
    sys.unsubscribe("BUZZER_ENABLED_CHANGED", update_enabled_ui)
    sys.unsubscribe("BUZZER_DURATION_VALUE", update_duration_ui)
    sys.unsubscribe("BUZZER_DURATION_CHANGED", update_duration_ui)
    sys.unsubscribe("BUZZER_VOLUME_VALUE", update_volume_ui)
    sys.unsubscribe("BUZZER_VOLUME_CHANGED", update_volume_ui)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
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
