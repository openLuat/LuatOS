--[[
@module  main_menu_win
@summary 主菜单页面模块
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil
local main_container, time_label, signal_img
local full_path, current_time = "", "08:00"
local StatusProvider = require "status_provider_app"

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 800, color = 0xF8F9FA, parent = airui.screen })

    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 60, color = 0x3F51B5 })
    signal_img = airui.image({ parent = status_bar, x = 430, y = 14, w = 40, h = 40, src = full_path })
    time_label = airui.label({ parent = status_bar, x = 140, y = 10, w = 200, h = 48, text = current_time, font_size = 40, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 内容区域
    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 480, h = 680, color = 0xF3F4F6 })

    -- 图标网格（5个应用，一行）
    local apps = {
        { name = "定位", win = "GPS", icon = "/luadb/dingwei.png" },
        { name = "IoT账户", win = "IOT_ACCOUNT", icon = "/luadb/denglu.png" },
        { name = "蓝牙", win = "BLUETOOTH", icon = "/luadb/lanya.png" },
        { name = "WiFi", win = "WIFI", icon = "/luadb/wifi.png" },
        { name = "FOTA", win = "FOTA", icon = "/luadb/FOTA.png" },
    }
    local cell_w = 96
    local start_x = (480 - (cell_w * 5)) / 2
    local cell_y = 50

    for i, app in ipairs(apps) do
        local x = start_x + (i-1) * cell_w
        local cell = airui.container({
            parent = content,
            x = x,
            y = cell_y,
            w = cell_w,
            h = 120,
            color = 0xF3F4F6,
            on_click = function()
                sys.publish("OPEN_" .. app.win .. "_WIN")
            end
        })
        airui.image({ parent = cell, x = (cell_w-48)/2, y = 10, w = 48, h = 48, src = app.icon })
        airui.label({
            parent = cell,
            x = 0,
            y = 70,
            w = cell_w,
            h = 30,
            text = app.name,
            font_size = 18,
            color = 0x000000,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 底部按钮栏
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 740, w = 480, h = 60, color = 0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x = 0, y = 0, w = 240, h = 60, color = 0x2195F6, on_click = function() exwin.close(win_id) end })
    airui.image({ parent = btn_left, x = 50, y = 14, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 90, y = 20, w = 100, h = 40, text = "首页", font_size = 24, color = 0xfefefe })

    local btn_right = airui.container({ parent = bottom_bar, x = 240, y = 0, w = 240, h = 60, color = 0xFF9A27 })
    airui.image({ parent = btn_right, x = 50, y = 14, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 90, y = 20, w = 100, h = 40, text = "主菜单", font_size = 24, color = 0xfefefe })
end

local function update_time()
    if not time_label then return end
    current_time = StatusProvider.get_time()
    time_label:set_text(current_time)
end

local function update_signal()
    local level = StatusProvider.get_signal_level()
    if not signal_img then return end
    local img_name = "wifixinhao" .. level .. ".png"
    local full_path = "/luadb/" .. img_name
    signal_img:set_src(full_path)
end

local function on_status_time_updated()
    update_time()
end

local function on_status_signal_updated()
    update_signal()
end

local function on_create()
    create_ui()
    update_time()
    update_signal()
    sys.timerLoopStart(update_time, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
end

local function on_destroy()
    sys.timerStop(update_time)
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    time_label, signal_img = nil, nil
end

local function on_get_focus()
    update_time()
    update_signal()
end

local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end
sys.subscribe("OPEN_MAIN_MENU_WIN", open_handler)