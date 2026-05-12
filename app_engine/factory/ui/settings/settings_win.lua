--[[
@module  settings_win
@summary 设置主页面窗口
@version 1.1 (自适应分辨率)
@date    2026.04.16
@author  江访
]]

require "settings_display_win"
require "settings_storage_win"
require "settings_about_win"
require "settings_sound_win"
require "wifi_list_win"
require "settings_iot_win"

local window_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 10
local card_w = 460
local card_h = 70
local card_spacing = 20

local COLOR_PRIMARY        = 0x007AFF
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
    margin = math.floor(screen_w * 0.02)
    card_w = screen_w - 2 * margin
    card_h = math.floor(screen_h * 0.09)
    card_spacing = math.floor(screen_h * 0.015)
end

local function build_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = COLOR_BG
    })

    -- 标题栏
    local tb = airui.container({
        parent = main_container,
        x = 0, y = 0,
        w = screen_w, h = math.floor(60 * _G.density_scale),
        color = COLOR_PRIMARY
    })
    local bb = airui.container({
        parent = tb,
        x = 10, y = 10,
        w = math.floor(50 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        color = COLOR_PRIMARY,
        on_click = function() exwin.close(window_id) end
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
        w = math.floor(100 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "设置",
        font_size = math.floor(32 * _G.density_scale),
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT
    })

    local th = math.floor(60 * _G.density_scale)
    local ct = airui.container({
        parent = main_container,
        x = 0, y = th,
        w = screen_w, h = screen_h - th,
        color = COLOR_BG
    })

    local function create_card(y, title, on_click)
        local card = airui.container({
            parent = ct,
            x = margin, y = y,
            w = card_w, h = card_h,
            color = COLOR_WHITE,
            radius = 8,
            on_click = on_click
        })
        local label_h = math.floor(30 * _G.density_scale)
        local label_y = math.floor((card_h - label_h) / 2)
        airui.label({
            parent = card,
            x = math.floor(20 * _G.density_scale), y = label_y,
            w = math.floor(200 * _G.density_scale), h = label_h,
            text = title,
            font_size = math.floor(24 * _G.density_scale),
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT
        })
        airui.label({
            parent = card,
            x = card_w - math.floor(50 * _G.density_scale), y = label_y,
            w = math.floor(30 * _G.density_scale), h = label_h,
            text = ">",
            font_size = math.floor(24 * _G.density_scale),
            color = COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    local is_air8000 = _G.model_str:find("Air8000") ~= nil

    local y = math.floor(20 * _G.density_scale)
    create_card(y, "IOT账号", function() sys.publish("OPEN_IOT_WIN") end)
    y = y + card_h + card_spacing
    create_card(y, "WiFi设置", function() sys.publish("OPEN_WIFI_WIN") end)
    y = y + card_h + card_spacing
    create_card(y, "显示亮度", function() sys.publish("OPEN_DISPLAY_WIN") end)
    y = y + card_h + card_spacing
    create_card(y, "存储", function() sys.publish("OPEN_STORAGE_WIN") end)
    y = y + card_h + card_spacing
    create_card(y, "系统更新", function()
        sys.publish("OPEN_SYSTEM_WIN")
        airui.msgbox({
            parent = ct,
            title = "提示",
            text = "正在开发中...",
            buttons = {"确定"},
            on_action = function(self) self:destroy() end
        })
    end)
    y = y + card_h + card_spacing
    if is_air8000 then
        create_card(y, "触摸音效", function() sys.publish("OPEN_SOUND_WIN") end)
        y = y + card_h + card_spacing
    end
    create_card(y, "关于设置", function() sys.publish("OPEN_ABOUT_WIN") end)
end

local function on_create() build_ui() end
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
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

sys.subscribe("OPEN_SETTINGS_WIN", open_handler)
