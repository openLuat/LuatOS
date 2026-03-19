-- lua - 首页

local win_id = nil
local main_container, time_label, date_label, temp_label, hum_label, air_label, signal_img, qrcode1
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
    main_container = airui.container({ x = 0, y = 0, w = 1024, h = 600, color = 0xF8F9FA, parent = airui.screen })
    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 1024, h = 60, color = 0x3F51B5 })

    signal_img = airui.image({ parent = status_bar, x = 920, y = 10, w = 40, h = 40, src = full_path })
    time_label = airui.label({ parent = status_bar, x = 400, y = 10, w = 200, h = 40, text = current_time, font_size = 36, color = 0xfefefe, align = airui.TEXT_ALIGN_CENTER })
    
    -- 中间日期显示
    date_label = airui.label({ parent = main_container, x = 400, y = 280, w = 200, h = 40, text = "", font_size = 24, color = 0x3d3d3d, align = airui.TEXT_ALIGN_CENTER })

    -- 内容区域
    local content = airui.container({ parent = main_container, x = 0, y = 60, w = 1024, h = 480, color = 0xF3F4F6 })

    -- 三个卡片
    card_temp = airui.container({
        parent = content,
        x = 50,
        y = 30,
        w = 280,
        h = 220,
        color = 0xffffff,
        radius = 15,
        on_click = function() show_history_chart("temperature") end
    })
    card_hum = airui.container({
        parent = content,
        x = 372,
        y = 30,
        w = 280,
        h = 220,
        color = 0xffffff,
        radius = 15,
        on_click = function() show_history_chart("humidity") end
    })
    card_air = airui.container({
        parent = content,
        x = 694,
        y = 30,
        w = 280,
        h = 220,
        color = 0xffffff,
        radius = 15,
        on_click = function() show_history_chart("air") end
    })

    -- 温度卡片
    airui.image({ parent = card_temp, x = 110, y = 20, w = 60, h = 60, src = "/luadb/wendu_1.png" })
    temp_label = airui.label({
        parent = card_temp,
        x = 20,
        y = 100,
        w = 160,
        h = 60,
        text = "未接入传感器",
        font_size = 16,
        color = 0xFF0000,
        align =
            airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_temp, x = 190, y = 110, w = 60, h = 40, text = "℃", font_size = 28, color = 0x000000 })
    airui.label({
        parent = card_temp,
        x = 20,
        y = 175,
        w = 240,
        h = 30,
        text = "当前温度",
        font_size = 22,
        color = 0x838383,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 湿度卡片
    airui.image({ parent = card_hum, x = 110, y = 20, w = 60, h = 60, src = "/luadb/shidu.png" })
    hum_label = airui.label({
        parent = card_hum,
        x = 20,
        y = 100,
        w = 160,
        h = 60,
        text = "未接入传感器",
        font_size = 16,
        color = 0xFF0000,
        align =
            airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_hum, x = 190, y = 110, w = 60, h = 40, text = "%", font_size = 28, color = 0x000000 })
    airui.label({
        parent = card_hum,
        x = 20,
        y = 175,
        w = 240,
        h = 30,
        text = "当前湿度",
        font_size = 22,
        color = 0x838383,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 空气质量卡片
    airui.image({ parent = card_air, x = 110, y = 20, w = 60, h = 60, src = "/luadb/kongqizhiliang.png" })
    air_label = airui.label({
        parent = card_air,
        x = 20,
        y = 100,
        w = 160,
        h = 60,
        text = "未接入传感器",
        font_size = 16,
        color = 0xFF0000,
        align =
            airui.TEXT_ALIGN_RIGHT
    })
    airui.label({ parent = card_air, x = 190, y = 110, w = 70, h = 40, text = "ppb", font_size = 28, color = 0x000000 })
    airui.label({
        parent = card_air,
        x = 20,
        y = 175,
        w = 240,
        h = 30,
        text = "空气质量",
        font_size = 22,
        color = 0x838383,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = content,
        x = 0,
        y = 280,
        w = 512,
        h = 30,
        text = "扫码查看设备云端数据",
        font_size = 20,
        color = 0x3d3d3d,
        align =
            airui.TEXT_ALIGN_CENTER
    })
    airui.label({
        parent = content,
        x = 512,
        y = 280,
        w = 512,
        h = 30,
        text = "扫码查看设备使用说明",
        font_size = 20,
        color = 0x3d3d3d,
        align =
            airui.TEXT_ALIGN_CENTER
    })

    -- 二维码 - 左侧云端数据二维码
    -- 使用默认URL初始化，收到aircloud_qrinfo后再更新
    local qr_data = aircloud_qr or "https://air.openluat.com"
    qrcode1 = airui.qrcode({ parent = content, x = 180, y = 320, size = 150, data = qr_data, dark_color = 0x000000, light_color = 0xFFFFFF, quiet_zone = true })
    -- 右侧使用说明二维码
    airui.qrcode({
        parent = content,
        x = 694,
        y = 320,
        size = 150,
        data =
        "https://gitee.com/openLuat/LuatOS/tree/master/module/Air1601/project/Air1601_turnkey_devboard",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    -- 底部按钮
    local bottom_bar = airui.container({ parent = main_container, x = 0, y = 540, w = 1024, h = 60, color = 0xffffff })
    local btn_left = airui.container({ parent = bottom_bar, x = 0, y = 0, w = 512, h = 60, color = 0xFF9A27 })
    airui.image({ parent = btn_left, x = 200, y = 10, w = 40, h = 40, src = "/luadb/home.png" })
    airui.label({ parent = btn_left, x = 260, y = 15, w = 100, h = 30, text = "首页", font_size = 24, color = 0xfefefe })
    local btn_right = airui.container({
        parent = bottom_bar,
        x = 512,
        y = 0,
        w = 512,
        h = 60,
        color = 0x2195F6,
        on_click = function() sys.publish("OPEN_MAIN_MENU_WIN") end
    })
    airui.image({ parent = btn_right, x = 200, y = 10, w = 40, h = 40, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 260, y = 15, w = 100, h = 30, text = "主菜单", font_size = 24, color = 0xfefefe })
end

-- 内部函数：更新时间
local function update_time()
    if not time_label then return end
    -- exwin.is_active 在页面刚打开时可能还是false，放宽判断，只检查控件是否存在
    -- 即使不活跃，更新控件也不会出问题，而且当获得焦点时on_get_focus会再次刷新
    local current_time = StatusProvider.get_time()
    time_label:set_text(current_time)
    
    -- 更新日期显示
    if date_label then
        local t = os.time()
        if t then
            local dt = os.date("*t", t)
            local current_date = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
            date_label:set_text(current_date)
        end
    end
end


-- 更新信号图标（由StatusProvider事件调用）
local function update_signal()
    local csq_level = StatusProvider.get_signal_level()
    log.info("idle_win", "update_signal called, csq_level=", csq_level)
    if not signal_img then 
        log.info("idle_win", "signal_img not initialized")
        return 
    end
    local signal_img_name = "4Gxinghao6.png" -- 默认无信号
    if csq_level > 0 and csq_level <= 5 then
        signal_img_name = "4Gxinghao" .. csq_level .. ".png"
    elseif csq_level >= 6 then
        signal_img_name = "4Gxinghao6.png"
    end
    local full_path = "/luadb/" .. signal_img_name
    log.info("idle_win", "setting signal image to", full_path)
    signal_img:set_src(full_path)
end

-- 处理StatusProvider的时间更新事件
local function on_status_time_updated()
    update_time()
end

-- 处理StatusProvider的日期更新事件
local function on_status_date_updated()
    update_time()
end

-- 处理StatusProvider的信号更新事件
local function on_status_signal_updated()
    update_signal()
end

-- 后台任务（全局）
local function aircloud_qr_update(qr)
    log.info("idle_win", "收到二维码更新:", qr)
    aircloud_qr = qr
    if exwin.is_active(win_id) and qrcode1 then
        log.info("idle_win", "更新二维码显示")
        qrcode1:set_data(aircloud_qr)
    else
        log.info("idle_win", "页面未激活或二维码未初始化，保存二维码数据")
    end
end


local function sensor_read_update(temp, hum, air)
    local t, h, v = temp, hum, air
    if exwin.is_active(win_id) then
        if temp_label then
            if t then
                temp_label:set_text(string.format("%.1f", t)); temp_label:set_color(0x000000); temp_label:set_font_size(48)
            else
                temp_label:set_text("未接入传感器"); temp_label:set_color(0xFF0000); temp_label:set_font_size(24)
            end
        end
        if hum_label then
            if h then
                hum_label:set_text(string.format("%.0f", h)); hum_label:set_color(0x000000); hum_label:set_font_size(48)
            else
                hum_label:set_text("未接入传感器"); hum_label:set_color(0xFF0000); hum_label:set_font_size(24)
            end
        end
        if air_label then
            if v then
                air_label:set_text(string.format("%d", v)); air_label:set_color(0x000000); air_label:set_font_size(48)
            else
                air_label:set_text("未接入传感器"); air_label:set_color(0xFF0000); air_label:set_font_size(24)
            end
        end
    end
end

-- 生命周期回调
local function on_create()
    create_ui()
    sys.timerLoopStart(update_time, 1000)
    sys.subscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.subscribe("STATUS_DATE_UPDATED", on_status_date_updated)
    sys.subscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    sys.publish("read_sensors_req")
    update_time()
    update_signal()
    -- 如果已经有二维码数据，立即更新显示
    if aircloud_qr ~= nil and qrcode1 then
        log.info("idle_win", "on_create: 设置已有二维码数据")
        qrcode1:set_data(aircloud_qr)
    end
end

local function on_destroy()
    sys.timerStop(update_time)
    sys.unsubscribe("STATUS_TIME_UPDATED", on_status_time_updated)
    sys.unsubscribe("STATUS_DATE_UPDATED", on_status_date_updated)
    sys.unsubscribe("STATUS_SIGNAL_UPDATED", on_status_signal_updated)
    if current_win then
        current_win:close()
        current_win = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    time_label, date_label, signal_img, qrcode1, temp_label, hum_label, air_label = nil, nil, nil, nil, nil, nil, nil
    card_temp, card_hum, card_air = nil, nil, nil
end

local function on_get_focus()
    -- 页面获得焦点时主动刷新一次
    update_time()
    update_signal()
    if aircloud_qr ~= nil and qrcode1 then
        log.info("idle_win", "on_get_focus: 更新二维码")
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
