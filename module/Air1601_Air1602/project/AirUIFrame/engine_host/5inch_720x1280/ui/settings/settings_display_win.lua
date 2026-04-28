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
        w = screen_w, h = math.floor(60 * _G.density_scale),
        color = 0x3F51B5
    })
    local btn_back = airui.container({
        parent = title_bar,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = 0x3F51B5,
        on_click = function() exwin.close(win_id) end
    })
    airui.label({
        parent = btn_back,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = title_bar,
        x = math.floor(60 * _G.density_scale), y = math.floor(14 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "显示与亮度",
        font_size = math.floor(32 * _G.density_scale),
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_LEFT
    })

    local title_h = math.floor(60 * _G.density_scale)
    local content = airui.container({
        parent = main_container,
        x = 0, y = title_h,
        w = screen_w, h = screen_h - title_h,
        color = 0xF5F5F5
    })

    -- 亮度卡片
    local card_brightness = airui.container({
        parent = content,
        x = margin, y = math.floor(20 * _G.density_scale),
        w = card_w, h = math.floor(140 * _G.density_scale),
        color = 0xFFFFFF,
        radius = 8
    })
    airui.label({
        parent = card_brightness,
        x = math.floor(20 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "亮度",
        font_size = math.floor(24 * _G.density_scale),
        color = 0x333333,
        align = airui.TEXT_ALIGN_LEFT
    })
    brightness_label = airui.label({
        parent = card_brightness,
        x = card_w - math.floor(80 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(60 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "50",
        font_size = math.floor(24 * _G.density_scale),
        color = 0x666666,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local btn_w = math.floor(60 * _G.density_scale)
    local btn_margin = math.floor(20 * _G.density_scale)
    local bar_x = btn_margin + btn_w + math.floor(10 * _G.density_scale)
    local bar_w = card_w - 2 * btn_margin - 2 * btn_w - math.floor(20 * _G.density_scale)

    airui.button({
        parent = card_brightness,
        x = btn_margin, y = math.floor(55 * _G.density_scale),
        w = btn_w, h = math.floor(40 * _G.density_scale),
        text = "-10",
        font_size = math.floor(20 * _G.density_scale),
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
        x = card_w - btn_margin - btn_w, y = math.floor(55 * _G.density_scale),
        w = btn_w, h = math.floor(40 * _G.density_scale),
        text = "+10",
        font_size = math.floor(20 * _G.density_scale),
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
        x = bar_x, y = math.floor(65 * _G.density_scale),
        w = bar_w, h = math.floor(25 * _G.density_scale),
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
