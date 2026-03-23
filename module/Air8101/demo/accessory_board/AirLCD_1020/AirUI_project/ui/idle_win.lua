--[[
@module  idle_win
@summary 首页窗口模块，显示系统状态和传感器数据
@version 2.0
@date    2026.03.23
@author  江访
@usage
本模块为系统首页窗口，主要功能包括：
1、显示当前时间，每秒自动更新；
2、显示WiFi信号强度，动态更新；
3、显示温度、湿度、空气质量传感器数据；
4、提供传感器卡片点击查看历史图表功能；
5、显示设备型号二维码；
6、显示合宙云二维码；
]]

local win_id = nil

local main_container, time_label, temp_label, hum_label, air_label, signal_img, qrcode1

local full_path, current_time = "", "08:00"

local card_temp, card_hum, card_air

local current_win = nil

local aircloud_qr = nil

local StatusProvider = require "status_provider_app"

local function show_history_chart(sensor_type)
    if not exwin.is_active(win_id) then return end
    if sensor_type == "temperature" then
        sys.publish("OPEN_TEMP_HISTORY_WIN")
    elseif sensor_type == "humidity" then
        sys.publish("OPEN_HUM_HISTORY_WIN")
    elseif sensor_type == "air" then
        sys.publish("OPEN_AIR_HISTORY_WIN")
    end
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 800, h = 480, color = 0xF8F9FA, parent = airui.screen })

    -- 顶部状态栏（高度60）
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 800, h = 60, color = 0x3F51B5 })

    signal_img = airui.image({ parent = status_bar, x = 750, y = 14, w = 40, h = 40, src = full_path })
    time_label = airui.label({ parent = status_bar, x = 350, y = 10, w = 200, h = 48, text = current_time, font_size = 40, color = 0xfefefe })

    -- 内容区域（y起始60，高度420）
    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 800, h = 420, color = 0xF3F4F6 })

    -- 三个卡片，宽高适当放大，间距调整
    card_temp = airui.container({
        parent = content,
        x = 30,
        y = 20,
        w = 230,
        h = 165,
        color = 0xffffff,
        radius = 12,
        on_click = function() show_history_chart("temperature") end
    })
    card_hum = airui.container({
        parent = content,
        x = 285,
        y = 20,
        w = 230,
        h = 165,
        color = 0xffffff,
        radius = 12,
        on_click = function() show_history_chart("humidity") end
    })
    card_air = airui.container({
        parent = content,
        x = 540,
        y = 20,
        w = 230,
        h = 165,
        color = 0xffffff,
        radius = 12,
        on_click = function() show_history_chart("air") end
    })

    -- 温度卡片
    airui.image({ parent = card_temp, x = 99, y = 12, w = 32, h = 32, src = "/luadb/wendu_1.png" })
    temp_label = airui.label({
        parent = card_temp,
        x = 10,
        y = 60,
        w = 130,
        h = 60,
        text = "未接入传感器",
        font_size = 24,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_temp, x = 150, y = 80, w = 50, h = 30, text = "℃", font_size = 20, color = 0x000000 })
    airui.label({
        parent = card_temp,
        x = 10,
        y = 130,
        w = 210,
        h = 25,
        text = "当前温度",
        font_size = 20,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 湿度卡片
    airui.image({ parent = card_hum, x = 99, y = 12, w = 32, h = 32, src = "/luadb/shidu.png" })
    hum_label = airui.label({
        parent = card_hum,
        x = 10,
        y = 60,
        w = 130,
        h = 60,
        text = "未接入传感器",
        font_size = 24,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_hum, x = 150, y = 80, w = 50, h = 30, text = "%", font_size = 20, color = 0x000000 })
    airui.label({
        parent = card_hum,
        x = 10,
        y = 130,
        w = 210,
        h = 25,
        text = "当前湿度",
        font_size = 20,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 空气质量卡片
    airui.image({ parent = card_air, x = 99, y = 12, w = 32, h = 32, src = "/luadb/kongqizhiliang.png" })
    air_label = airui.label({
        parent = card_air,
        x = 10,
        y = 60,
        w = 130,
        h = 60,
        text = "未接入传感器",
        font_size = 24,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_air, x = 150, y = 80, w = 60, h = 30, text = "ppb", font_size = 20, color = 0x000000 })
    airui.label({
        parent = card_air,
        x = 10,
        y = 130,
        w = 210,
        h = 25,
        text = "空气质量",
        font_size = 20,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = content,
        x = 0,
        y = 200,
        w = 400,
        h = 30,
        text = "扫码查看设备云端数据",
        font_size = 20,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = content,
        x = 400,
        y = 200,
        w = 400,
        h = 30,
        text = "扫码查看设备使用说明",
        font_size = 20,
        color = 0x3d3d3d,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 二维码
    qrcode1 = airui.qrcode({ parent = content, x = 135, y = 220, size = 130, data = aircloud_qr, dark_color = 0x000000, light_color = 0xFFFFFF, quiet_zone = true })
    airui.qrcode({
        parent = content,
        x = 535,
        y = 220,
        size = 130,
        data = "https://docs.openluat.com/air8101/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    -- 底部按钮栏（y起始420，高度60）
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 420, w = 800, h = 60, color = 0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x = 0, y = 0, w = 400, h = 60, color = 0xFF9A27 })
    airui.image({ parent = btn_left, x = 133, y = 14, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 180, y = 15, w = 120, h = 40, text = "首页", font_size = 24, color = 0xfefefe })
    local btn_right = airui.container({
        parent = bottom_bar,
        x = 400,
        y = 0,
        w = 400,
        h = 60,
        color = 0x2195F6,
        on_click = function() sys.publish("OPEN_MAIN_MENU_WIN") end
    })
    airui.image({ parent = btn_right, x = 133, y = 14, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 180, y = 15, w = 120, h = 40, text = "主菜单", font_size = 24, color = 0xfefefe })
end

local function update_time()
    if not time_label then return end
    local current_time = StatusProvider.get_time()
    time_label:set_text(current_time)
end

-- 更新WiFi信号图标
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

local function aircloud_qr_update(qr)
    aircloud_qr = qr
    if exwin.is_active(win_id) and qrcode1 then
        qrcode1:set_data(aircloud_qr)
    end
end

local function sensor_read_update(temp, hum, air)
    local t, h, v = temp, hum, air
    if exwin.is_active(win_id) then
        if temp_label then
            if t then
                temp_label:set_text(string.format("%.1f", t)); temp_label:set_color(0x000000); temp_label:set_font_size(36)
            else
                temp_label:set_text("未接入传感器"); temp_label:set_color(0xFF0000); temp_label:set_font_size(24)
            end
        end
        if hum_label then
            if h then
                hum_label:set_text(string.format("%.0f", h)); hum_label:set_color(0x000000); hum_label:set_font_size(36)
            else
                hum_label:set_text("未接入传感器"); hum_label:set_color(0xFF0000); hum_label:set_font_size(24)
            end
        end
        if air_label then
            if v then
                air_label:set_text(string.format("%d", v)); air_label:set_color(0x000000); air_label:set_font_size(36)
            else
                air_label:set_text("未接入传感器"); air_label:set_color(0xFF0000); air_label:set_font_size(24)
            end
        end
    end
end

local function on_create()
    create_ui()
    sys.timerLoopStart(update_time, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    sys.publish("read_sensors_req")
    update_time()
    update_signal()
end

local function on_destroy()
    sys.timerStop(update_time)
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    if current_win then
        current_win:close()
        current_win = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    time_label, signal_img, qrcode1, temp_label, hum_label, air_label = nil, nil, nil, nil, nil, nil
    card_temp, card_hum, card_air = nil, nil, nil
end

local function on_get_focus()
    update_time()
    update_signal()
    if aircloud_qr ~= nil then
        qrcode1:set_data(aircloud_qr)
    end
end

local function on_lose_focus()
end

local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_IDLE_WIN", open_handler)
sys.subscribe("aircloud_qrinfo", aircloud_qr_update)
sys.subscribe("ui_sensor_data", sensor_read_update)