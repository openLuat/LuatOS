--[[
@module  settings_win
@summary 设置主页面窗口
@version 1.1 (自适应分辨率)
@date    2026.04.16
@author  江访
]]
-- naming: fn(2-5char), var(2-4char)

-- require "settings_display_win"
require "settings_storage_win"
require "settings_about_win"
-- require "settings_sound_win"
require "wifi_list_win"
require "settings_iot_win"

local wid = nil
local mc
local sw, sh = 480, 800
local mg = 10
local cw = 460
local ch = 70
local csp = 20

local COLOR_PRIMARY        = 0x007AFF
local COLOR_BG             = 0xF5F5F5
local COLOR_CARD           = 0xFFFFFF
local COLOR_TEXT           = 0x333333
local COLOR_TEXT_SECONDARY = 0x757575
local COLOR_DIVIDER        = 0xE0E0E0
local COLOR_WHITE          = 0xFFFFFF

local function up_sz()
    local rotation = airui.get_rotation()
    local phys_w, phys_h = lcd.getSize()
    if rotation == 0 or rotation == 180 then
        sw, sh = phys_w, phys_h
    else
        sw, sh = phys_h, phys_w
    end
    mg = math.floor(sw * 0.02)
    cw = sw - 2 * mg
    ch = math.floor(sh * 0.09)
    csp = math.floor(sh * 0.015)
end

local function cui()
    up_sz()
    mc = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = sw, h = sh,
        color = COLOR_BG
    })

    -- 标题栏
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
        w = math.floor(100 * _G.density_scale), h = math.floor(40 * _G.density_scale),
        text = "设置",
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

    local function mk(y, title, on_click)
        local card = airui.container({
            parent = ct,
            x = mg, y = y,
            w = cw, h = ch,
            color = COLOR_WHITE,
            radius = 8,
            on_click = on_click
        })
        local lh = math.floor(30 * _G.density_scale)
        local ly = math.floor((ch - lh) / 2)
        airui.label({
            parent = card,
            x = math.floor(20 * _G.density_scale), y = ly,
            w = math.floor(200 * _G.density_scale), h = lh,
            text = title,
            font_size = math.floor(24 * _G.density_scale),
            color = COLOR_TEXT,
            align = airui.TEXT_ALIGN_LEFT
        })
        airui.label({
            parent = card,
            x = cw - math.floor(50 * _G.density_scale), y = ly,
            w = math.floor(30 * _G.density_scale), h = lh,
            text = ">",
            font_size = math.floor(24 * _G.density_scale),
            color = COLOR_TEXT_SECONDARY,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    local a8k = _G.model_str:find("Air8000") ~= nil

    local y = math.floor(20 * _G.density_scale)
    mk(y, "IOT账号", function() sys.publish("OPEN_IOT_WIN") end)
    y = y + ch + csp
    mk(y, "WiFi设置", function() sys.publish("OPEN_WIFI_WIN") end)
    -- y = y + ch + csp
    -- mk(y, "显示亮度", function() sys.publish("OPEN_DISPLAY_WIN") end)
    y = y + ch + csp
    mk(y, "存储", function() sys.publish("OPEN_STORAGE_WIN") end)
    y = y + ch + csp
    mk(y, "系统更新", function()
        sys.publish("OPEN_SYSTEM_WIN")
        airui.msgbox({
            parent = ct,
            title = "提示",
            text = "正在开发中...",
            buttons = {"确定"},
            on_action = function(self) self:destroy() end
        })
    end)
    y = y + ch + csp
    if a8k then
        mk(y, "触摸音效", function() sys.publish("OPEN_SOUND_WIN") end)
        y = y + ch + csp
    end
    mk(y, "关于设置", function() sys.publish("OPEN_ABOUT_WIN") end)
end

local function oc() cui() end
local function od()
    if mc then mc:destroy(); mc = nil end
end
local function ogf() end
local function olf() end

local function oh()
    wid = exwin.open({
        on_create = oc,
        on_destroy = od,
        on_lose_focus = olf,
        on_get_focus = ogf,
    })
end

sys.subscribe("OPEN_SETTINGS_WIN", oh)
