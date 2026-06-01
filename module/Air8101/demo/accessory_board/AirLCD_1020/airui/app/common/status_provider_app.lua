--[[
@module  status_provider_app
@summary 状态提供器应用模块，负责收集和管理系统状态信息
@version 1.0
@date    2026.03.23
@author  江访
@usage
本模块为状态提供器应用模块，主要功能包括：
1、管理时间信息，每秒更新当前时间；
2、管理WiFi信号强度，根据连接状态和RSSI动态更新信号等级；
3、管理传感器数据（温度、湿度、空气质量），存储历史数据；
4、提供状态查询接口供其他模块调用；
5、发布状态更新事件供UI系统响应；

对外接口：
1、StatusProvider.get_time()：获取当前时间
2、StatusProvider.get_signal_level()：获取WiFi信号等级（0-4）
3、StatusProvider.get_sensor_latest()：获取最新传感器数据
4、StatusProvider.get_history(sensor_type)：获取传感器历史数据
]]

-- 状态提供器应用模块
local StatusProvider = {}

-- 历史数据存储表，用于存储传感器历史数据
local history = {
    temperature = {}, -- 温度历史数据数组
    humidity    = {}, -- 湿度历史数据数组
    air         = {}  -- 空气质量历史数据数组
}

-- 历史数据最大存储数量
local MAX_HISTORY = 20

-- WiFi信号相关变量
local wifi_connected = false       -- WiFi连接状态
local wifi_signal_level = 0        -- 当前信号等级（0-4，0表示断开或无效）
local wifi_rssi = nil              -- 当前RSSI值（dBm）
local wifi_timer = nil             -- 定时器ID，用于周期性更新信号等级

-- 当前时间字符串，格式为"HH:MM"
local current_time = "08:00"

--[[
更新时间函数，每秒调用一次
]]
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        current_time = string.format("%02d:%02d", dt.hour, dt.min)
        sys.publish("STATUS_TIME_UPDATED", current_time)
    end
end

--[[
根据RSSI计算信号等级（0-4）
阈值参考：强信号 > -60，中等信号 -80 ~ -60，差信号 < -80
等级映射：
    4级: RSSI > -60
    3级: -70 < RSSI <= -60
    2级: -80 < RSSI <= -70
    1级: RSSI <= -80
    0级: 未连接或无效
]]
local function rssi_to_level(rssi)
    if not rssi then return 0 end
    if rssi > -60 then
        return 4
    elseif rssi > -70 then
        return 3
    elseif rssi > -80 then
        return 2
    elseif rssi <= -80 then
        return 1
    else
        return 0
    end
end

--[[
更新WiFi信号等级（从wlan模块获取RSSI，计算等级，若变化则发布事件）
]]
local function update_wifi_signal()
    if not wifi_connected then
        -- 未连接时等级为0，如果之前不是0则发布事件
        if wifi_signal_level ~= 0 then
            wifi_signal_level = 0
            sys.publish("STATUS_SIGNAL_UPDATED", wifi_signal_level)
        end
        return
    end

    -- 获取当前RSSI
    local info = wlan.getInfo()
    if info and info.rssi then
        wifi_rssi = info.rssi
        local new_level = rssi_to_level(wifi_rssi)
        if wifi_signal_level ~= new_level then
            wifi_signal_level = new_level
            sys.publish("STATUS_SIGNAL_UPDATED", wifi_signal_level)
        end
    else
        -- 获取失败时保持原等级
        log.warn("status_provider", "Failed to get WiFi RSSI")
    end
end

--[[
WiFi STA事件处理函数
]]
local function sta_event(evt, data)
    log.info("status_provider", "WLAN_STA_INC", evt, data)
    if evt == "CONNECTED" then
        -- 连接成功
        wifi_connected = true
        -- 立即更新一次信号等级
        update_wifi_signal()
        -- 启动定时器，每秒更新一次信号等级（可根据需要调整间隔）
        if wifi_timer then
            sys.timerStop(update_wifi_signal)
        end
        wifi_timer = sys.timerLoopStart(update_wifi_signal, 1000)
    elseif evt == "DISCONNECTED" then
        -- 断开连接
        wifi_connected = false
        -- 停止定时器
        if wifi_timer then
            sys.timerStop(update_wifi_signal)
            wifi_timer = nil
        end
        -- 设置等级为0并发布事件
        if wifi_signal_level ~= 0 then
            wifi_signal_level = 0
            sys.publish("STATUS_SIGNAL_UPDATED", wifi_signal_level)
        end
    end
end

--[[
传感器数据处理函数，响应传感器数据更新事件
]]
local function handle_sensor_data(temp, hum, air)
    -- 温度有效性验证函数
    local function is_valid_temp(v) return v and v > -40 and v < 100 end
    -- 湿度有效性验证函数
    local function is_valid_hum(v) return v and v >= 0 and v <= 100 end
    -- 空气质量有效性验证函数
    local function is_valid_air(v) return v and v >= 0 and v < 5000 end

    if is_valid_temp(temp) then
        local temp_int = math.floor(temp)
        table.insert(history.temperature, temp_int)
        if #history.temperature > MAX_HISTORY then table.remove(history.temperature, 1) end
        log.info("status_provider", "temperature history stored", temp, "->", temp_int)
    end
    if is_valid_hum(hum) then
        local hum_int = math.floor(hum)
        table.insert(history.humidity, hum_int)
        if #history.humidity > MAX_HISTORY then table.remove(history.humidity, 1) end
        log.info("status_provider", "humidity history stored", hum, "->", hum_int)
    end
    if is_valid_air(air) then
        table.insert(history.air, air)
        if #history.air > MAX_HISTORY then table.remove(history.air, 1) end
    end
    sys.publish("STATUS_SENSOR_UPDATED", temp, hum, air)
end

--[[
获取当前时间接口
]]
function StatusProvider.get_time()
    return current_time
end

--[[
获取WiFi信号等级接口
]]
function StatusProvider.get_signal_level()
    return wifi_signal_level
end

--[[
获取最新传感器数据接口
]]
function StatusProvider.get_sensor_latest()
    local t = history.temperature[#history.temperature]
    local h = history.humidity[#history.humidity]
    local a = history.air[#history.air]
    return t, h, a
end

--[[
获取传感器历史数据接口
]]
function StatusProvider.get_history(sensor_type)
    return history[sensor_type] or {}
end

--[[
模块初始化函数，在模块加载时自动执行
]]
local function init()
    -- 启动时间更新定时器
    sys.timerLoopStart(update_time, 1000)
    -- 订阅传感器数据
    sys.subscribe("ui_sensor_data", handle_sensor_data)
    -- 订阅WiFi STA事件
    sys.subscribe("WLAN_STA_INC", sta_event)
    -- 立即更新时间
    update_time()
    -- 初始时获取一次WiFi状态（如果已经连接）
    local info = wlan.getInfo()
    if info and info.ssid then
        -- 假设已经连接
        wifi_connected = true
        update_wifi_signal()
        wifi_timer = sys.timerLoopStart(update_wifi_signal, 1000)
    else
        wifi_connected = false
        wifi_signal_level = 0
    end
end
init()

return StatusProvider