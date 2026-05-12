--[[
@naming  us_s=update_screen_size c_ui=create_ui | wid=win_id mc=main_container brb=brightness_bar brl=brightness_label sw=screen_w sh=screen_h m=margin cw=card_w
@module  settings_display_win
@summary 显示与亮度子页面
@version 1.1 (自适应分辨率)
@date    2026.04.16
@author  江访
]]

local wid = nil
local mc
local brb
local brl
local sw, sh = 480, 800
local m = 15
local cw = 460

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

local function us_s()
    local rot = airui.get_rotation()
    local pw, ph = lcd.getSize()
    if rot == 0 or rot == 180 then
        sw, sh = pw, ph
    else
        sw, sh = ph, pw
    end
    m = math.floor(sw * 0.03)
    cw = sw - 2 * m
end

local function update_brightness_ui(val)
    if brb then
        brb:set_value(val)
    end
    if brl then
        brl:set_text(tostring(val))
    end
    log.info("s_dsp", "UI更新亮度: " .. val)
end

local function c_ui()
    us_s()
    mc = airui.container({
        x = 0, y = 0,
        w = sw, h = sh,
        color = COLOR_BG,
        parent = airui.screen
    })

    local tb = airui.container({
        parent = mc,
        x = 0, y = 0,
        w = sw, h = math.floor(60 * _G.density_scale),
        color = COLOR_PRIMARY
    })
    local bb = airui.container({
        parent = tb,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(wid) end
    })
    airui.label({
        parent = bb,
        x = 0, y = math.floor(5 * _G.density_scale),
        w = math.floor(50 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "<",
        font_size = math.floor(28 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = tb,
        x = math.floor(60 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "显示与亮度",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local th = math.floor(60 * _G.density_scale)
    local ct = airui.container({
        parent = mc,
        x = 0, y = th,
        w = sw, h = sh - th,
        color = COLOR_BG
    })

    local cbr = airui.container({
        parent = ct,
        x = m, y = math.floor(20 * _G.density_scale),
        w = cw, h = math.floor(140 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    airui.label({
        parent = cbr,
        x = math.floor(20 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(100 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "亮度",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    brl = airui.label({
        parent = cbr,
        x = cw - math.floor(80 * _G.density_scale), y = math.floor(10 * _G.density_scale),
        w = math.floor(60 * _G.density_scale), h = math.floor(30 * _G.density_scale),
        text = "50",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })

    local bw = math.floor(60 * _G.density_scale)
    local bm = math.floor(20 * _G.density_scale)
    local bx = bm + bw + math.floor(10 * _G.density_scale)
    local brw = cw - 2 * bm - 2 * bw - math.floor(20 * _G.density_scale)

    airui.button({
        parent = cbr,
        x = bm, y = math.floor(55 * _G.density_scale),
        w = bw, h = math.floor(40 * _G.density_scale),
        text = "-10",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_PRIMARY,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function() sys.publish("DISPLAY_BRIGHTNESS_DECREASE") end
    })
    airui.button({
        parent = cbr,
        x = cw - bm - bw, y = math.floor(55 * _G.density_scale),
        w = bw, h = math.floor(40 * _G.density_scale),
        text = "+10",
        font_size = math.floor(20 * _G.density_scale),
        style = {
            bg_color = COLOR_DIVIDER,
            pressed_bg_color = COLOR_PRIMARY,
            text_color = COLOR_TEXT,
            radius = 8,
            border_width = 1,
            border_color = COLOR_DIVIDER
        },
        on_click = function() sys.publish("DISPLAY_BRIGHTNESS_INCREASE") end
    })
    brb = airui.bar({
        parent = cbr,
        x = bx, y = math.floor(65 * _G.density_scale),
        w = brw, h = math.floor(25 * _G.density_scale),
        min = 0, max = 100,
        value = 50,
        color = COLOR_PRIMARY,
        bg_color = COLOR_DIVIDER
    })
end

local function on_create()
    c_ui()
    sys.publish("DISPLAY_BRIGHTNESS_GET")
    sys.subscribe("DISPLAY_BRIGHTNESS_CHANGED", update_brightness_ui)
    sys.subscribe("DISPLAY_BRIGHTNESS_VALUE", update_brightness_ui)
end

local function on_destroy()
    sys.unsubscribe("DISPLAY_BRIGHTNESS_CHANGED", update_brightness_ui)
    sys.unsubscribe("DISPLAY_BRIGHTNESS_VALUE", update_brightness_ui)
    if mc then
        mc:destroy()
        mc = nil
    end
    brb = nil
    brl = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    wid = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_DISPLAY_WIN", open_handler)
