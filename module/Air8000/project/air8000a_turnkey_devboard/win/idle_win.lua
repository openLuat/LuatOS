-- lua - 首页

local win_id = nil
local main_container, time_label, temp_label, hum_label, air_label, signal_img, qrcode1
local full_path, current_time = "/luadb/4Gxinghao6.png", "08:00"
local card_temp, card_hum, card_air
local current_win = nil -- 图表窗口
local aircloud_qr = nil
local StatusProvider = require "status_provider_app"

-- 内部函数：显示历史图表
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

-- 内部函数：创建UI
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 320, color = 0xF8F9FA, parent = airui.screen })
    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5 })

    signal_img = airui.image({ parent = status_bar, x = 430, y = 4, w = 32, h = 32, src = full_path })
    time_label = airui.label({ parent = status_bar, x = 188, y = 4, w = 100, h = 32, text = current_time, font_size = 30, color = 0xfefefe })

    -- 内容区域
    local content = airui.container({ parent = main_container, x = 0, y = 40, w = 480, h = 240, color = 0xF3F4F6 })

    -- 三个卡片
    card_temp = airui.container({
        parent = content,
        x = 15,
        y = 10,
        w = 140,
        h = 110,
        color = 0xffffff,
        radius = 10,
        on_click = function() show_history_chart("temperature") end
    })
    card_hum = airui.container({
        parent = content,
        x = 170,
        y = 10,
        w = 140,
        h = 110,
        color = 0xffffff,
        radius = 10,
        on_click = function() show_history_chart("humidity") end
    })
    card_air = airui.container({
        parent = content,
        x = 325,
        y = 10,
        w = 140,
        h = 110,
        color = 0xffffff,
        radius = 10,
        on_click = function() show_history_chart("air") end
    })

    -- 温度卡片
    airui.image({ parent = card_temp, x = 54, y = 8, w = 32, h = 32, src = "/luadb/wendu_1.png" })
    temp_label = airui.label({
        parent = card_temp,
        x = 10,
        y = 45,
        w = 80,
        h = 42,
        text = "未接入传感器",
        font_size = 16,
        color = 0xFF0000,
        align =
            airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_temp, x = 100, y = 60, w = 30, h = 20, text = "℃", font_size = 16, color = 0x000000 })
    airui.label({
        parent = card_temp,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "当前温度",
        font_size = 16,
        color = 0x838383,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 湿度卡片
    airui.image({ parent = card_hum, x = 54, y = 8, w = 32, h = 32, src = "/luadb/shidu.png" })
    hum_label = airui.label({
        parent = card_hum,
        x = 10,
        y = 45,
        w = 80,
        h = 42,
        text = "未接入传感器",
        font_size = 16,
        color = 0xFF0000,
        align =
            airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_hum, x = 100, y = 60, w = 30, h = 20, text = "%", font_size = 16, color = 0x000000 })
    airui.label({
        parent = card_hum,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "当前湿度",
        font_size = 16,
        color = 0x838383,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 空气质量卡片
    airui.image({ parent = card_air, x = 54, y = 8, w = 32, h = 32, src = "/luadb/kongqizhiliang.png" })
    air_label = airui.label({
        parent = card_air,
        x = 10,
        y = 45,
        w = 80,
        h = 42,
        text = "未接入传感器",
        font_size = 16,
        color = 0xFF0000,
        align =
            airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_air, x = 95, y = 60, w = 40, h = 20, text = "ppb", font_size = 16, color = 0x000000 })
    airui.label({
        parent = card_air,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "空气质量",
        font_size = 16,
        color = 0x838383,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = content,
        x = 0,
        y = 130,
        w = 240,
        h = 20,
        text = "扫码查看设备云端数据",
        font_size = 16,
        color = 0x3d3d3d,
        align =
            airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = content,
        x = 240,
        y = 130,
        w = 240,
        h = 20,
        text = "扫码查看设备使用说明",
        font_size = 16,
        color = 0x3d3d3d,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 二维码
    qrcode1 = airui.qrcode({ parent = content, x = 80, y = 150, size = 90, data = aircloud_qr, dark_color = 0x000000, light_color = 0xFFFFFF, quiet_zone = true })
    airui.qrcode({
        parent = content,
        x = 320,
        y = 150,
        size = 90,
        data =
        "https://docs.openluat.com/air8000/product/air8000a_turnkey_devboard/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    -- 底部按钮
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 280, w = 480, h = 40, color = 0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x = 0, y = 0, w = 240, h = 40, color = 0xFF9A27 })
    airui.image({ parent = btn_left, x = 53, y = 4, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 100, y = 10, w = 80, h = 30, text = "首页", font_size = 20, color = 0xfefefe })
    local btn_right = airui.container({
        parent = bottom_bar,
        x = 240,
        y = 0,
        w = 240,
        h = 40,
        color = 0x2195F6,
        on_click = function() sys.publish("OPEN_MAIN_MENU_WIN") end
    })
    airui.image({ parent = btn_right, x = 53, y = 4, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 100, y = 10, w = 100, h = 30, text = "主菜单", font_size = 20, color = 0xfefefe })
end

-- 内部函数：更新时间
local function update_time()
    if not time_label then return end
    -- exwin.is_active 在页面刚打开时可能还是false，放宽判断，只检查控件是否存在
    -- 即使不活跃，更新控件也不会出问题，而且当获得焦点时on_get_focus会再次刷新
    local current_time = StatusProvider.get_time()
    time_label:set_text(current_time)
end


-- 更新信号图标（由StatusProvider事件调用）
local function update_signal()
    local csq_level = StatusProvider.get_signal_level()
    if not signal_img then return end
    local signal_img_name = "4Gxinghao6.png" -- 默认无信号
    if csq_level > 0 and csq_level <= 5 then
        signal_img_name = "4Gxinghao" .. csq_level .. ".png"
    elseif csq_level >= 6 then
        signal_img_name = "4Gxinghao6.png"
    end
    local full_path = "/luadb/" .. signal_img_name
    signal_img:set_src(full_path)
end

-- 处理StatusProvider的时间更新事件
local function on_status_time_updated()
    update_time()
end

-- 处理StatusProvider的信号更新事件
local function on_status_signal_updated()
    update_signal()
end

-- 后台任务（全局）
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
                temp_label:set_text("未接入传感器"); temp_label:set_color(0xFF0000); temp_label:set_font_size(16)
            end
        end
        if hum_label then
            if h then
                hum_label:set_text(string.format("%.0f", h)); hum_label:set_color(0x000000); hum_label:set_font_size(36)
            else
                hum_label:set_text("未接入传感器"); hum_label:set_color(0xFF0000); hum_label:set_font_size(16)
            end
        end
        if air_label then
            if v then
                air_label:set_text(string.format("%d", v)); air_label:set_color(0x000000); air_label:set_font_size(36)
            else
                air_label:set_text("未接入传感器"); air_label:set_color(0xFF0000); air_label:set_font_size(16)
            end
        end
    end
end

-- 生命周期回调
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
    -- 页面获得焦点时主动刷新一次
    update_time()
    update_signal()
    if aircloud_qr ~= nil then
        qrcode1:set_data(aircloud_qr)
    end
    -- update_signal() 内部已经处理了set_src，这里不需要重复设置
end

local function on_lose_focus()
    -- 无需操作
end

-- 订阅打开首页的消息
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
