--[[
@naming  us_s=update_screen_size c_ui=create_ui | wid=win_id mc=main_container sw=screen_w sh=screen_h m=margin cw=card_w tgl=toggle_switch ds=duration_slider dl=duration_label vs=volume_slider vl=volume_label
@module  settings_sound_win
@summary 声音与触摸子页面
@version 1.0
@date    2026.04.24
@author  江访
]]

local wid = nil
local mc
local sw, sh = 480, 800
local m = 15
local cw = 460

local tgl
local ds, dl
local vs, vl

local COLOR_PRIMARY        = 0x007AFF
local COLOR_ACCENT         = 0xFF9800
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

local function c_ui()
    us_s()
    local bw = math.floor(50 * _G.density_scale)
    local bm = math.floor(20 * _G.density_scale)
    local bx = bm + bw + math.floor(10 * _G.density_scale)
    local brw = cw - 2 * bm - 2 * bw - math.floor(20 * _G.density_scale)
    mc = airui.container({
        parent = airui.screen,
        x = 0,
        y = 0,
        w = sw,
        h = sh,
        color = COLOR_BG
    })

    local tb = airui.container({
        parent = mc,
        x = 0,
        y = 0,
        w = sw,
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
        on_click = function() exwin.close(wid) end
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
        parent = mc,
        x = 0,
        y = th,
        w = sw,
        h = sh - th,
        color = COLOR_BG
    })

    local ctg = airui.container({
        parent = ct,
        x = m,
        y = math.floor(20 * _G.density_scale),
        w = cw,
        h = math.floor(70 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    airui.label({
        parent = ctg,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(20 * _G.density_scale),
        w = math.floor(200 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "触摸反馈",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    tgl = airui.switch({
        parent = ctg,
        x = cw - math.floor(80 * _G.density_scale),
        y = math.floor(15 * _G.density_scale),
        w = math.floor(60 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        checked = true,
        on_change = function(self)
            sys.publish("BUZZER_SET_ENABLED", self:get_state())
        end
    })

    local cdr = airui.container({
        parent = ct,
        x = m,
        y = math.floor(110 * _G.density_scale),
        w = cw,
        h = math.floor(140 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    airui.label({
        parent = cdr,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "按下发声时长",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    dl = airui.label({
        parent = cdr,
        x = cw - math.floor(120 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(100 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "50ms",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.button({
        parent = cdr,
        x = bm,
        y = math.floor(55 * _G.density_scale),
        w = bw,
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
    ds = airui.bar({
        parent = cdr,
        x = bx,
        y = math.floor(65 * _G.density_scale),
        w = brw,
        h = math.floor(25 * _G.density_scale),
        min = 20,
        max = 500,
        value = 50,
        indicator_color = COLOR_ACCENT,
        bg_color = COLOR_DIVIDER
    })
    airui.button({
        parent = cdr,
        x = cw - bm - bw,
        y = math.floor(55 * _G.density_scale),
        w = bw,
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
        parent = cdr,
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

    local cvl = airui.container({
        parent = ct,
        x = m,
        y = math.floor(270 * _G.density_scale),
        w = cw,
        h = math.floor(140 * _G.density_scale),
        color = COLOR_WHITE,
        radius = 8
    })
    airui.label({
        parent = cvl,
        x = math.floor(20 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(200 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "声音大小",
        font_size = math.floor(24 * _G.density_scale),
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })
    vl = airui.label({
        parent = cvl,
        x = cw - math.floor(120 * _G.density_scale),
        y = math.floor(10 * _G.density_scale),
        w = math.floor(100 * _G.density_scale),
        h = math.floor(30 * _G.density_scale),
        text = "50",
        font_size = math.floor(22 * _G.density_scale),
        color = COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.button({
        parent = cvl,
        x = bm,
        y = math.floor(55 * _G.density_scale),
        w = bw,
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
    vs = airui.bar({
        parent = cvl,
        x = bx,
        y = math.floor(65 * _G.density_scale),
        w = brw,
        h = math.floor(25 * _G.density_scale),
        min = 10,
        max = 100,
        value = 50,
        indicator_color = COLOR_ACCENT,
        bg_color = COLOR_DIVIDER
    })
    airui.button({
        parent = cvl,
        x = cw - bm - bw,
        y = math.floor(55 * _G.density_scale),
        w = bw,
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
        parent = cvl,
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

local function update_enabled_ui(val)
    if not tgl then return end
    if tgl:get_state() == val then return end
    tgl:set_state(val)
end

local function uev(val) update_enabled_ui(val) end

local function update_duration_ui(val)
    if dl then
        dl:set_text(tostring(val) .. "ms")
    end
    if ds then
        ds:set_value(val)
    end
end

local function update_volume_ui(val)
    if vl then
        vl:set_text(tostring(val))
    end
    if vs then
        vs:set_value(val)
    end
end

local function on_create()
    c_ui()
    sys.publish("BUZZER_GET_ENABLED")
    sys.publish("BUZZER_GET_DURATION")
    sys.publish("BUZZER_GET_VOLUME")
    sys.subscribe("BUZZER_ENABLED_VALUE", uev)
    sys.subscribe("BUZZER_ENABLED_CHANGED", update_enabled_ui)
    sys.subscribe("BUZZER_DURATION_VALUE", update_duration_ui)
    sys.subscribe("BUZZER_DURATION_CHANGED", update_duration_ui)
    sys.subscribe("BUZZER_VOLUME_VALUE", update_volume_ui)
    sys.subscribe("BUZZER_VOLUME_CHANGED", update_volume_ui)
end

local function on_destroy()
    sys.unsubscribe("BUZZER_ENABLED_VALUE", uev)
    sys.unsubscribe("BUZZER_ENABLED_CHANGED", update_enabled_ui)
    sys.unsubscribe("BUZZER_DURATION_VALUE", update_duration_ui)
    sys.unsubscribe("BUZZER_DURATION_CHANGED", update_duration_ui)
    sys.unsubscribe("BUZZER_VOLUME_VALUE", update_volume_ui)
    sys.unsubscribe("BUZZER_VOLUME_CHANGED", update_volume_ui)
    if mc then
        mc:destroy()
        mc = nil
    end
    tgl = nil
    ds = nil
    dl = nil
    vs = nil
    vl = nil
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

sys.subscribe("OPEN_SOUND_WIN", open_handler)
