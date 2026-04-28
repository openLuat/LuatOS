--[[
@module  settings_display_win
@summary 显示与亮度子页面
@version 1.1 (自适应分辨率)
@date    2026.04.16
]]

require "settings_display_app"

local win_id = nil
local main_container
local brightness_bar
local brightness_label
local screen_w, screen_h = 480, 800
local margin = 15
local card_w = 460

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

local function update_brightness_ui(value)
    if brightness_bar then
        brightness_bar:set_value(value)
    end
    if brightness_label then
        brightness_label:set_text(tostring(value))
    end
    log.info("settings_display_win", "UI更新亮度: " .. value)
end

local function create_ui()
    update_screen_size()
    main_container = airui.container({
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF5F5F5,
        parent = airui.screen
    })

    -- 标题栏 (同其他窗口)
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = 60,
        color = 0x3F51B5
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = 50, h = 40,
        color = 0x3F51B5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = 5,
        w = 50, h = 30,
        text = "<",
        font_size = 28,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        x = 60, y = 14,
        w = 200, h = 40,
        text = "显示与亮度",
        font_size = 32,
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })

    local content = airui.container({
        parent = main_container,
        x = 0, y = 60,
        w = screen_w, h = screen_h - 60,
        color = 0xF5F5F5
    })

    -- 亮度卡片
    local card_brightness = airui.container({
        parent = content,
        x = margin, y = 20,
        w = card_w, h = 140,
        color = 0xFFFFFF,
        radius = 8
    })
    airui.label({
        parent = card_brightness,
        x = 20, y = 10,
        w = 100, h = 30,
        text = "亮度",
        font_size = 24,
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    brightness_label = airui.label({
        parent = card_brightness,
        x = card_w - 80, y = 10,
        w = 60, h = 30,
        text = "50",
        font_size = 24,
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local btn_w = 60
    local btn_margin = 20
    local bar_x = btn_margin + btn_w + 10
    local bar_w = card_w - 2 * btn_margin - 2 * btn_w - 20

    airui.button({
        parent = card_brightness,
        x = btn_margin, y = 55,
        w = btn_w, h = 40,
        text = "-10",
        font_size = 20,
        style = {
            bg_color = 0xE0E0E0,
            pressed_bg_color = 0x2196F3,
            text_color = 0x333333,
            radius = 8,
            border_width = 1,
            border_color = 0xBDBDBD
        },
        on_click = function() sys.publish("DISPLAY_BRIGHTNESS_DECREASE") end
    })
    airui.button({
        parent = card_brightness,
        x = card_w - btn_margin - btn_w, y = 55,
        w = btn_w, h = 40,
        text = "+10",
        font_size = 20,
        style = {
            bg_color = 0xE0E0E0,
            pressed_bg_color = 0x2196F3,
            text_color = 0x333333,
            radius = 8,
            border_width = 1,
            border_color = 0xBDBDBD
        },
        on_click = function() sys.publish("DISPLAY_BRIGHTNESS_INCREASE") end
    })
    brightness_bar = airui.bar({
        parent = card_brightness,
        x = bar_x, y = 65,
        w = bar_w, h = 25,
        min = 0, max = 100,
        value = 50,
        color = 0x2196F3,
        bg_color = 0xE0E0E0
    })
end

local function on_create()
    create_ui()
    sys.publish("DISPLAY_BRIGHTNESS_GET")
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    brightness_bar = nil
    brightness_label = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("DISPLAY_BRIGHTNESS_CHANGED", update_brightness_ui)
sys.subscribe("DISPLAY_BRIGHTNESS_VALUE", update_brightness_ui)
sys.subscribe("OPEN_DISPLAY_WIN", open_handler)