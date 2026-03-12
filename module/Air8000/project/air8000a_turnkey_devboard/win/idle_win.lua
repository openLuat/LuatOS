-- idle_win_lua - 首页

local win_id = nil
local main_container, time_label, temp_label, hum_label, air_label, signal_img, qrcode1
local card_temp, card_hum, card_air
local time_timer, signal_timer
local temp_history, hum_history, air_history = {}, {}, {}
local MAX_HISTORY = 20
local current_win = nil -- 图表窗口



-- 内部函数：显示历史图表
local function show_history_chart(sensor_type)
    if not exwin.is_active(win_id) then return end
    if current_win then
        current_win:close(); current_win = nil
    end
    local title, history, y_min, y_max, unit
    if sensor_type == "temperature" then
        title = "温度历史"; history = temp_history; y_min = 0; y_max = 50; unit = "℃"
    elseif sensor_type == "humidity" then
        title = "湿度历史"; history = hum_history; y_min = 0; y_max = 100; unit = "%"
    elseif sensor_type == "air" then
        title = "空气质量历史"; history = air_history; y_min = 0; y_max = 1000; unit = "ppb"
    else
        return
    end
    local win = airui.win({
        parent = airui.screen,
        title = title,
        w = 400,
        h = 300,
        close_btn = true,
        auto_center = true,
        on_close = function() current_win = nil end
    })
    local chart = airui.chart({
        x = 30,
        y = 0,
        w = 300,
        h = 170,
        y_min = y_min,
        y_max = y_max,
        point_count = MAX_HISTORY,
        line_color = 0x00b4ff,
        line_width = 2,
        hdiv = 5,
        vdiv = 5,
        legend = false,
        update_mode = "shift",
        x_axis = { enable = true, min = 0, max = MAX_HISTORY, ticks = 5, unit = "次" },
        y_axis = { enable = true, min = y_min, max = y_max, ticks = 5, unit = unit }
    })
    if #history > 0 then chart:set_values(1, history) end
    win:add_content(chart)
    current_win = win
end

-- 内部函数：创建UI
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 320, color = 0xF8F9FA, parent = airui.screen })
    -- 顶部状态栏
    local status_bar = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 40, color = 0x3F51B5 })
    signal_img = airui.image({ parent = status_bar, x = 430, y = 4, w = 32, h = 32, src = lte_csq or "/luadb/4Gxinghao6.png" })
    time_label = airui.label({ parent = status_bar, x = 188, y = 4, w = 100, h = 32, text = show_time or "--:--", font_size = 30, color = 0xfefefe })

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
        on_click = function() sys.publish("OPEN_ALL_APP_WIN") end
    })
    airui.image({ parent = btn_right, x = 53, y = 4, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({ parent = btn_right, x = 100, y = 10, w = 100, h = 30, text = "全部应用", font_size = 20, color = 0xfefefe })
end

-- 内部函数：更新时间
local function update_time()
    local t = os.time()
    local dt = os.date("*t", t)
    show_time = string.format("%02d:%02d", dt.hour, dt.min)
    if not exwin.is_active(win_id) then return end
    if time_label then time_label:set_text(show_time) end
end


-- 更新信号图标（由定时器或SIM事件调用）
local function update_signal()
    -- 使用全局 sim_present，如果未定义则视为 false
    if not sim_present then
        lte_csq = "4Gxinghao6.png"
    else
        local csq = mobile.csq()
        if csq == 99 or csq <= 5 then
            lte_csq = "4Gxinghao5.png"
        elseif csq <= 10 then
            lte_csq = "4Gxinghao1.png"
        elseif csq <= 15 then
            lte_csq = "4Gxinghao2.png"
        elseif csq <= 20 then
            lte_csq = "4Gxinghao3.png"
        else
            lte_csq = "4Gxinghao4.png"
        end
    end
    if not exwin.is_active(win_id) or not signal_img then return end
    signal_img:set_src("/luadb/" .. lte_csq)
end



-- 内部函数：处理SIM卡状态
local function handle_sim_ind(status, value)
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" then
        sim_present = false
    end
    update_signal()
end

-- 更新历史数组
local function update_history(history, value)
    if value then
        table.insert(history, value)
        if #history > MAX_HISTORY then table.remove(history, 1) end
    end
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
                update_history(temp_history, t)
            else
                temp_label:set_text("未接入传感器"); temp_label:set_color(0xFF0000); temp_label:set_font_size(16)
            end
        end
        if hum_label then
            if h then
                hum_label:set_text(string.format("%.0f", h)); hum_label:set_color(0x000000); hum_label:set_font_size(36)
                update_history(hum_history, h)
            else
                hum_label:set_text("未接入传感器"); hum_label:set_color(0xFF0000); hum_label:set_font_size(16)
            end
        end
        if air_label then
            if v then
                air_label:set_text(string.format("%d", v)); air_label:set_color(0x000000); air_label:set_font_size(36)
                update_history(air_history, v)
            else
                air_label:set_text("未接入传感器"); air_label:set_color(0xFF0000); air_label:set_font_size(16)
            end
        end
    end
end

-- 生命周期回调
function idle_win_on_create()
    create_ui()
    time_timer = sys.timerLoopStart(update_time, 1000)
    signal_timer = sys.timerLoopStart(update_signal, 2000)
    sys.subscribe("SIM_IND", handle_sim_ind)
    sys.publish("read_sensors_req")
    update_time()
    update_signal()
    if qrcode1 ~= nil then
         qrcode1:set_data(aircloud_qr)
    end
end

function idle_win_on_destroy()
    if time_timer then
        sys.timerStop(time_timer); time_timer = nil
    end
    if signal_timer then
        sys.timerStop(signal_timer); signal_timer = nil
    end
    sys.unsubscribe("SIM_IND", handle_sim_ind)
    if current_win then
        current_win:close(); current_win = nil
    end
    if main_container then
        main_container:destroy(); main_container = nil
    end
    time_label, signal_img, qrcode1, temp_label, hum_label, air_label = nil, nil, nil, nil, nil, nil
    card_temp, card_hum, card_air = nil, nil, nil
end

function idle_win_on_get_focus()
    -- 页面获得焦点时主动刷新一次
    update_time()
    update_signal()
end

function idle_win_on_lose_focus()
    -- 无需操作
end

-- 订阅打开首页的消息
local function open_idle_win_handler()
    win_id = exwin.open({
        on_create = idle_win_on_create,
        on_destroy = idle_win_on_destroy,
        on_lose_focus = idle_win_on_lose_focus,
        on_get_focus = idle_win_on_get_focus,
    })
end

sys.subscribe("OPEN_IDLE_WIN", open_idle_win_handler)
sys.subscribe("aircloud_qrinfo", aircloud_qr_update)
sys.subscribe("ui_sensor_data", sensor_read_update)
