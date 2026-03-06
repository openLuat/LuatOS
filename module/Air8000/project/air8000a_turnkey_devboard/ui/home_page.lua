-- 页面模块
local home_page = {}

-- UI控件引用（初始为nil）
local main_container
local time_label
local temp_label, hum_label, air_label
local signal_img         -- 信号图标控件
local qrcode1            -- 二维码控件

-- 定时器句柄
local time_timer
local signal_timer

-- 状态标志
local active = false     -- 页面是否激活（UI已创建且可见）

-- 传感器数据（默认文本）
local temp_val, hum_val, voc_val = "未接入传感器", "未接入传感器", "未接入传感器"

-- 卡片容器（用于点击事件）
local card_temp, card_hum, card_air

-- 历史数据存储（最多20条）
local temp_history = {}
local hum_history = {}
local air_history = {}
local MAX_HISTORY = 20

-- 当前打开的图表窗口（避免重叠）
local current_win = nil

-- 更新时间标签
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        local hour = dt.hour
        local min = dt.min
        local time_str = string.format("%02d:%02d", hour, min)
        if time_label then
            time_label:set_text(time_str)
        end
    end
end

-- 显示历史数据图表窗口
local function show_history_chart(sensor_type)
    if not active then return end  -- 页面未激活时不操作

    -- 关闭之前打开的窗口
    if current_win then
        current_win:close()
        current_win = nil
    end

    local title, history, y_min, y_max, unit
    if sensor_type == "temperature" then
        title = "温度历史"
        history = temp_history
        y_min = 0
        y_max = 50
        unit = "℃"
    elseif sensor_type == "humidity" then
        title = "湿度历史"
        history = hum_history
        y_min = 0
        y_max = 100
        unit = "%"
    elseif sensor_type == "air" then
        title = "空气质量历史"
        history = air_history
        y_min = 0
        y_max = 1000
        unit = "ppb"
    else
        return
    end

    -- 创建窗口
    local win = airui.win({
        parent = airui.screen,
        title = title,
        w = 400,
        h = 300,
        close_btn = true,
        auto_center = true,
        style = {radius = 10, pad = 10},
        on_close = function()
            current_win = nil
        end
    })

    -- 创建图表
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
        x_axis = {
            enable = true,
            min = 0,
            max = MAX_HISTORY,
            ticks = 5,
            unit = "次"
        },
        y_axis = {
            enable = true,
            min = y_min,
            max = y_max,
            ticks = 5,
            unit = unit
        }
    })

    if #history > 0 then
        chart:set_values(1, history)
    end

    win:add_content(chart)
    current_win = win
end

-- 创建UI
function home_page.create_ui()
    -- 主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 480,
        h = 320,
        color = 0xF8F9FA,
        parent = airui.screen,
    })

    -- 顶部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 480,
        h = 40,
        color = 0x3F51B5,
    })

    -- 信号图标
    signal_img = airui.image({
        parent = status_bar,
        x = 430,
        y = 4,
        w = 32,
        h = 32,
        src = "/luadb/4Gxinghao6.png", -- 默认无卡图标
    })

    -- 时间标签
    time_label = airui.label({
        parent = status_bar,
        x = 188,
        y = 4,
        w = 100,
        h = 32,
        text = "--:--",
        font_size = 30,
        color = 0xfefefe,
    })

    -- 中间内容区域
    local content = airui.container({
        parent = main_container,
        x = 0,
        y = 40,
        w = 480,
        h = 240,
        color = 0xF3F4F6,
    })

    -- 三个卡片容器
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
        h = 35,
        text = temp_val,
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_temp,
        x = 100,
        y = 60,
        w = 30,
        h = 16,
        text = "℃",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_temp,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "当前温度",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 湿度卡片
    airui.image({ parent = card_hum, x = 54, y = 8, w = 32, h = 32, src = "/luadb/shidu.png" })
    hum_label = airui.label({
        parent = card_hum,
        x = 10,
        y = 45,
        w = 80,
        h = 35,
        text = hum_val,
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_hum,
        x = 100,
        y = 60,
        w = 30,
        h = 18,
        text = "%",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_hum,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "当前湿度",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 空气质量卡片
    airui.image({ parent = card_air, x = 54, y = 8, w = 32, h = 32, src = "/luadb/kongqizhiliang.png" })
    air_label = airui.label({
        parent = card_air,
        x = 10,
        y = 45,
        w = 80,
        h = 36,
        text = voc_val,
        font_size = 16,
        color = 0xFF0000,
        align = airui.TEXT_ALIGN_RIGHT
    })
    airui.label({
        parent = card_air,
        x = 95,
        y = 60,
        w = 40,
        h = 16,
        text = "ppb",
        font_size = 16,
        color = 0x000000,
        align = airui.TEXT_ALIGN_LEFT
    })
    airui.label({
        parent = card_air,
        x = 10,
        y = 88,
        w = 130,
        h = 20,
        text = "空气质量",
        font_size = 16,
        color = 0x838383,
        align = airui.TEXT_ALIGN_CENTER
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
        align = airui.TEXT_ALIGN_CENTER
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
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 使用全局 aircloud_qr，如果为 nil 则提供空字符串避免二维码创建失败
    local qr_initial_data = aircloud_qr or ""
    qrcode1 = airui.qrcode({
        parent = content,
        x = 80,
        y = 150,
        size = 90,
        data = qr_initial_data,
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    local qrcode2 = airui.qrcode({
        parent = content,
        x = 320,
        y = 150,
        size = 90,
        data = "https://docs.openluat.com/air8000/product/air8000a_turnkey_devboard/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    -- 底部按钮区域
    local bottom_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 280,
        w = 480,
        h = 40,
        color = 0xffffff,
    })

    local btn_left = airui.container({
        parent = bottom_bar,
        x = 0,
        y = 0,
        w = 240,
        h = 40,
        color = 0xFF9A27,
    })
    airui.image({ parent = btn_left, x = 53, y = 4, w = 32, h = 32, src = "/luadb/home.png" })
    airui.label({
        parent = btn_left,
        x = 100,
        y = 10,
        w = 80,
        h = 30,
        text = "首页",
        font_size = 20,
        color = 0xfefefe,
    })

    local btn_right = airui.container({
        parent = bottom_bar,
        x = 240,
        y = 0,
        w = 240,
        h = 40,
        color = 0x2195F6,
        on_click = function() _G.show_page("all_app") end
    })
    airui.image({ parent = btn_right, x = 53, y = 4, w = 32, h = 32, src = "/luadb/quanbuyingyong.png" })
    airui.label({
        parent = btn_right,
        x = 100,
        y = 10,
        w = 100,
        h = 30,
        text = "全部应用",
        font_size = 20,
        color = 0xfefefe,
    })
end

-- 更新信号图标（由定时器或SIM事件调用）
local function update_signal()
    if not signal_img then return end  -- 控件不存在则跳过
    local img_name
    -- 使用全局 sim_present，如果未定义则视为 false
    if not sim_present then
        img_name = "4Gxinghao6.png"
    else
        local csq = mobile.csq()
        if csq == 99 or csq <= 5 then
            img_name = "4Gxinghao5.png"
        elseif csq <= 10 then
            img_name = "4Gxinghao1.png"
        elseif csq <= 15 then
            img_name = "4Gxinghao2.png"
        elseif csq <= 20 then
            img_name = "4Gxinghao3.png"
        else
            img_name = "4Gxinghao4.png"
        end
    end
    if img_name then
        signal_img:set_src("/luadb/" .. img_name)
    end
end

-- 处理SIM卡状态变化
local function handle_sim_ind(status, value)
    -- 更新全局 SIM 状态变量
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" then
        sim_present = false
    end
    -- 仅当页面激活且信号图标存在时更新
    if active and signal_img then
        update_signal()
    end
end

-- 更新历史数组的辅助函数
local function update_history(history, value)
    if value then
        table.insert(history, value)
        if #history > MAX_HISTORY then
            table.remove(history, 1)
        end
    end
end

-- 二维码更新任务（全局启动）
local function aircloud_qr_task()
    while true do
        local result
        result, aircloud_qr = sys.waitUntil("aircloud_qrinfo")
        -- 只有页面激活且控件存在时才更新
        if active and qrcode1 then
            qrcode1:set_data(aircloud_qr)
        end
    end
end


-- 传感器读取任务（全局启动）
local function sensor_read_task()
    while true do
        local result, t, h, v = sys.waitUntil("ui_sensor_data")
        if active then
            -- 更新温度
            if temp_label then
                if t ~= nil then
                    temp_label:set_text(string.format("%.1f", t))
                    temp_label:set_color(0x000000)
                    temp_label:set_font_size(36)
                    update_history(temp_history, t)
                else
                    temp_label:set_text("未接入传感器")
                    temp_label:set_color(0xFF0000)
                    temp_label:set_font_size(16)
                end
            end
            -- 更新湿度
            if hum_label then
                if h ~= nil then
                    hum_label:set_text(string.format("%.0f", h))
                    hum_label:set_color(0x000000)
                    hum_label:set_font_size(36)
                    update_history(hum_history, h)
                else
                    hum_label:set_text("未接入传感器")
                    hum_label:set_color(0xFF0000)
                    hum_label:set_font_size(16)
                end
            end
            -- 更新空气质量
            if air_label then
                if v ~= nil then
                    air_label:set_text(string.format("%d", v))
                    air_label:set_color(0x000000)
                    air_label:set_font_size(36)
                    update_history(air_history, v)
                else
                    air_label:set_text("未接入传感器")
                    air_label:set_color(0xFF0000)
                    air_label:set_font_size(16)
                end
            end
        end
    end
end

-- 页面初始化
function home_page.init()
    -- 创建UI
    home_page.create_ui()
    active = true   -- 标记页面已激活

    -- 立即刷新一次
    update_time()
    update_signal()

    -- 启动定时器
    time_timer = sys.timerLoopStart(update_time, 1000)
    signal_timer = sys.timerLoopStart(update_signal, 2000)

    -- 订阅SIM卡事件
    sys.subscribe("SIM_IND", handle_sim_ind)

    -- 触发传感器读取
    sys.publish("read_sensors_req")
end

-- 页面清理
function home_page.cleanup()
    active = false   -- 先标记为非激活，阻止后续UI操作

    -- 停止定时器
    if time_timer then
        sys.timerStop(time_timer)
        time_timer = nil
    end
    if signal_timer then
        sys.timerStop(signal_timer)
        signal_timer = nil
    end

    -- 取消SIM事件订阅
    sys.unsubscribe("SIM_IND", handle_sim_ind)

    -- 关闭图表窗口
    if current_win then
        current_win:close()
        current_win = nil
    end

    -- 销毁主容器及其所有子控件
    if main_container then
        main_container:destroy()
        main_container = nil
    end

    -- 清空所有控件引用
    time_label = nil
    signal_img = nil
    qrcode1 = nil
    temp_label = nil
    hum_label = nil
    air_label = nil
    card_temp = nil
    card_hum = nil
    card_air = nil
end

-- 启动后台任务（保留在文件末尾，全局启动）
sys.taskInit(aircloud_qr_task)
sys.taskInit(sensor_read_task)

return home_page