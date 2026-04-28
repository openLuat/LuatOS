--[[
@module  settings_win
@summary 设置主页面窗口
@version 1.1 (自适应分辨率)
@date    2026.04.16
]]

require "settings_display_win"
require "settings_storage_win"
require "settings_about_win"
require "settings_sound_win"

local win_id = nil
local main_container
local screen_w, screen_h = 480, 800
local margin = 10
local card_w = 460
local card_h = 70
local card_spacing = 20

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
    card_h = math.floor(screen_h * 0.09)  -- 约 9% 高度
    card_spacing = math.floor(screen_h * 0.015)
end

local function create_ui()
    update_screen_size()
    main_container = airui.container({
        parent = airui.screen,
        x = 0, y = 0,
        w = screen_w, h = screen_h,
        color = 0xF5F5F5
    })

    -- 标题栏
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
        w = 100, h = 40,
        text = "设置",
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

    local function create_setting_card(y, title, on_click)
        local card = airui.container({
            parent = content,
            x = margin, y = y,
            w = card_w, h = card_h,
            color = 0xFFFFFF,
            radius = 8,
            on_click = on_click
        })
        airui.label({
            parent = card,
            x = 20, y = (card_h - 30)/2,
            w = 200, h = 30,
            text = title,
            font_size = 24,
            color = 0x333333,
            align = airui.TEXT_ALIGN_LEFT
        })
        airui.label({
            parent = card,
            x = card_w - 50, y = (card_h - 30)/2,
            w = 30, h = 30,
            text = ">",
            font_size = 24,
            color = 0x999999,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    local y = 20
    create_setting_card(y, "显示与亮度", function() sys.publish("OPEN_DISPLAY_WIN") end)
    y = y + card_h + card_spacing
    create_setting_card(y, "系统与更新", function()
        sys.publish("OPEN_SYSTEM_WIN")
        airui.msgbox({
            parent = content,
            title = "提示",
            text = "正在开发中...",
            buttons = {"确定"},
            on_action = function(self) self:destroy() end
        })
    end)
    y = y + card_h + card_spacing
    create_setting_card(y, "存储", function() sys.publish("OPEN_STORAGE_WIN") end)
    y = y + card_h + card_spacing
    create_setting_card(y, "声音与触摸", function() sys.publish("OPEN_SOUND_WIN") end)
    y = y + card_h + card_spacing
    create_setting_card(y, "关于设备", function() sys.publish("OPEN_ABOUT_WIN") end)
end

local function on_create() create_ui() end
local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
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

sys.subscribe("OPEN_SETTINGS_WIN", open_handler)