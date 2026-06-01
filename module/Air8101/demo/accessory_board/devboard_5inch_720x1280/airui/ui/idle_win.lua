-- idle_win.lua
--[[
@module  idle_win
@summary 首页窗口模块，显示时间日期、二维码和常用应用
@version 1.0
@date    2026.03.26
@author  江访
]]

local win_id = nil

local main_container, time_label, big_time_label, date_label, signal_img, qrcode1, qrcode2
local aircloud_qr = nil  -- 存储合宙云二维码数据

local full_path = ""
local StatusProvider = require "status_provider_app"

-- 常用应用列
local apps = {
    { name = "定位", win = "GPS", icon = "/luadb/dingwei.png" },
    { name = "IoT账户", win = "IOT_ACCOUNT", icon = "/luadb/denglu.png" },
    { name = "蓝牙", win = "BLUETOOTH", icon = "/luadb/lanya.png" },
    { name = "WiFi", win = "WIFI", icon = "/luadb/wifi.png" },
    { name = "FOTA", win = "FOTA", icon = "/luadb/FOTA.png" },
}

local function open_app(win_name)
    if not exwin.is_active(win_id) then return end
    sys.publish("OPEN_" .. win_name .. "_WIN")
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 720, h = 1280, color = 0xF8F9FA, parent = airui.screen })

    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 720, h = 80, color = 0x3F51B5 })
    signal_img = airui.image({ parent = status_bar, x = 670, y = 20, w = 40, h = 40, src = full_path })
    time_label = airui.label({ parent = status_bar, x = 260, y = 16, w = 200, h = 48, text = "08:00", font_size = 44, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })

    -- 内容区域
    local content = airui.container({ parent = main_container, x = 0, y = 80, w = 720, h = 1120, color = 0xF3F4F6 })

    -- 大时间
    big_time_label = airui.label({
        parent = content,
        x = 0,
        y = 60,
        w = 720,
        h = 90,
        text = "08:00",
        font_size = 96,
        color = 0x000000,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 日期和星期
    date_label = airui.label({
        parent = content,
        x = 0,
        y = 160,
        w = 720,
        h = 40,
        text = "1970-01-01 星期四",
        font_size = 24,
        color = 0x666666,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 两个二维码（并排）
    local qr_size = 130
    local spacing = 40
    local total_width = qr_size * 2 + spacing
    local start_x = (720 - total_width) / 2
    local qr_y = 230

    -- 创建二维码时使用 aircloud_qr（初始为 nil）
    qrcode1 = airui.qrcode({
        parent = content,
        x = start_x,
        y = qr_y,
        size = qr_size,
        data = aircloud_qr,
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })
    airui.label({
        parent = content,
        x = start_x,
        y = qr_y + qr_size + 8,
        w = qr_size,
        h = 30,
        text = "设备云端数据",
        font_size = 16,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })

    qrcode2 = airui.qrcode({
        parent = content,
        x = start_x + qr_size + spacing,
        y = qr_y,
        size = qr_size,
        data = "https://docs.openluat.com/air8101/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })
    airui.label({
        parent = content,
        x = start_x + qr_size + spacing,
        y = qr_y + qr_size + 8,
        w = qr_size,
        h = 30,
        text = "使用说明",
        font_size = 16,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 常用应用图标（一行5个）
    local cell_w = 100
    local start_x_apps = (720 - cell_w * 5) / 2
    local apps_y = qr_y + qr_size + 70
    for i, app in ipairs(apps) do
        local x = start_x_apps + (i-1) * cell_w
        local cell = airui.container({
            parent = content,
            x = x,
            y = apps_y,
            w = cell_w,
            h = 100,
            color = 0xF3F4F6,
            on_click = function() open_app(app.win) end
        })
        airui.image({ parent = cell, x = (cell_w-48)/2, y = 10, w = 48, h = 48, src = app.icon })
        airui.label({
            parent = cell,
            x = 0,
            y = 65,
            w = cell_w,
            h = 30,
            text = app.name,
            font_size = 16,
            color = 0x000000,
            align = airui.TEXT_ALIGN_CENTER
        })
    end

    -- 底部按钮栏
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 1200, w = 720, h = 80, color = 0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x = 0, y = 0, w = 360, h = 80, color = 0xFF9A27 })
    airui.image({ parent = btn_left, x = 130, y = 24, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 170, y = 24, w = 100, h = 40, text = "首页", font_size = 28, color = 0xfefefe })

    local btn_right = airui.container({
        parent = bottom_bar,
        x = 360,
        y = 0,
        w = 360,
        h = 80,
        color = 0x2195F6,
        on_click = function() sys.publish("OPEN_MAIN_MENU_WIN") end
    })
    airui.image({ parent = btn_right, x = 130, y = 24, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 170, y = 24, w = 100, h = 40, text = "主菜单", font_size = 28, color = 0xfefefe })
end

-- 更新时间、日期、星期
local function update_time_date()
    if not time_label or not big_time_label or not date_label then return end
    local time_str = StatusProvider.get_time()
    local date_str = StatusProvider.get_date()
    local weekday_str = StatusProvider.get_weekday()
    time_label:set_text(time_str)
    big_time_label:set_text(time_str)
    date_label:set_text(date_str .. " " .. weekday_str)
end

-- 更新WiFi信号图标
local function update_signal()
    local level = StatusProvider.get_signal_level()
    if not signal_img then return end
    local img_name = "wifixinhao" .. level .. ".png"
    local full_path = "/luadb/" .. img_name
    signal_img:set_src(full_path)
end

-- 状态事件回调
local function on_status_time_updated()
    update_time_date()
end

local function on_status_signal_updated()
    update_signal()
end

local function aircloud_qr_update(qr)
    aircloud_qr = qr
    if exwin.is_active(win_id) and qrcode1 then
        qrcode1:set_data(aircloud_qr)
    end
end

local function on_create()
    create_ui()
    update_time_date()
    update_signal()
    sys.timerLoopStart(update_time_date, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    sys.subscribe("AIRCLOUD_QRINFO", aircloud_qr_update)
end

local function on_destroy()
    sys.timerStop(update_time_date)
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    sys.unsubscribe("AIRCLOUD_QRINFO", aircloud_qr_update)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    time_label, big_time_label, date_label, signal_img, qrcode1, qrcode2 = nil, nil, nil, nil, nil, nil
    aircloud_qr = nil
end

local function on_get_focus()
    update_time_date()
    update_signal()
    if aircloud_qr ~= nil then
        qrcode1:set_data(aircloud_qr)
    end
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

sys.subscribe("OPEN_IDLE_WIN", open_handler)