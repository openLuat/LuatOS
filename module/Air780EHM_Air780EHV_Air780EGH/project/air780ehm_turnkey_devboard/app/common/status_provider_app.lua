--[[
@module  status_provider_app
@summary 状态提供器应用模块，负责收集和管理系统状态信息
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为状态提供器应用模块，主要功能包括：
1、管理时间信息，每秒更新当前时间；
2、管理信号强度信息，每2秒更新信号等级；
3、管理传感器数据（温度、湿度、空气质量），存储历史数据；
4、提供状态查询接口供其他模块调用；
5、发布状态更新事件供UI系统响应；

对外接口：
1、StatusProvider.get_time()：获取当前时间
2、StatusProvider.get_signal_level()：获取信号等级
3、StatusProvider.get_sensor_latest()：获取最新传感器数据
4、StatusProvider.get_history(sensor_type)：获取传感器历史数据
]]

-- 状态提供器应用模块
local StatusProvider = {}

-- 历史数据存储表，用于存储传感器历史数据
local history = {
    temperature = {},  -- 温度历史数据数组
    humidity    = {},  -- 湿度历史数据数组
    air         = {}   -- 空气质量历史数据数组
}

-- 历史数据最大存储数量
local MAX_HISTORY = 20

-- 当前信号等级，-1表示无SIM卡
local csq_level = -1

-- SIM卡是否存在标志
local sim_present = false

-- 当前时间字符串，格式为"HH:MM"
local current_time = "08:00"

--[[
更新时间函数，每秒调用一次

@local
@function update_time
@summary 更新当前时间并发布时间更新事件
@return nil

@usage
-- 内部定时器调用，每秒执行一次
-- 获取系统时间，格式化为"HH:MM"字符串
-- 发布"STATUS_TIME_UPDATED"事件，携带当前时间字符串
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
更新信号等级函数，每2秒调用一次

@local
@function update_signal
@summary 更新信号强度等级并发布信号更新事件
@return nil

@usage
-- 内部定时器调用，每2秒执行一次
-- 根据SIM卡状态和CSQ值计算信号等级（1-5级）
-- 信号等级映射规则：
--   CSQ=99或CSQ≤5：等级1（信号极差）
--   5<CSQ≤10：等级2（信号差）
--   10<CSQ≤15：等级3（信号一般）
--   15<CSQ≤20：等级4（信号好）
--   CSQ>20：等级5（信号极好）
-- 当信号等级发生变化时，发布"STATUS_SIGNAL_UPDATED"事件
]]
local function update_signal()
    local old_level = csq_level
    if not sim_present then
        csq_level = -1
        log.info("status_provider", "no sim, set level -1")
    else
        local csq = mobile.csq()
        -- log.info("status_provider", "csq raw =", csq)
        if csq == 99 or csq <= 5 then
            csq_level = 1
        elseif csq <= 10 then
            csq_level = 2
        elseif csq <= 15 then
            csq_level = 3
        elseif csq <= 20 then
            csq_level = 4
        else
            csq_level = 5
        end
        -- log.info("status_provider", "mapped level =", csq_level)
    end
    if old_level ~= csq_level then
        sys.publish("STATUS_SIGNAL_UPDATED", csq_level)
    end
end

--[[
SIM卡状态处理函数，响应SIM卡状态变化事件

@local
@function handle_sim_ind
@param status string SIM卡状态，可能的值："RDY"（就绪）、"NORDY"（未就绪）
@param value any 状态相关值，具体含义取决于状态类型
@return nil

@usage
-- 订阅"SIM_IND"事件，当SIM卡状态变化时调用
-- 状态为"RDY"时，设置sim_present为true（SIM卡存在）
-- 状态为"NORDY"时，设置sim_present为false（SIM卡不存在）
-- 每次状态变化后立即调用update_signal()更新信号等级
]]
local function handle_sim_ind(status, value)
    log.info("status_provider", "SIM_IND", status, value or "")
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" then
        sim_present = false
    end
    update_signal()  -- 立即更新一次
end

--[[
传感器数据处理函数，响应传感器数据更新事件

@local
@function handle_sensor_data
@summary 处理传感器数据，进行有效性过滤和历史数据存储
@param temp number 温度值（摄氏度）
@param hum number 湿度值（百分比）
@param air number 空气质量值（整数）
@return nil

@usage
-- 订阅"ui_sensor_data"事件，当传感器数据更新时调用
-- 对每个传感器数据进行有效性验证：
--   温度：-40℃到100℃之间为有效
--   湿度：0%到100%之间为有效
--   空气质量：0到5000之间为有效
-- 有效数据存入历史数组，超过MAX_HISTORY条时移除最旧数据
-- 温度湿度数据向下取整存储，适配AirUI折线图不支持小数的问题
-- 发布"STATUS_SENSOR_UPDATED"事件，携带原始传感器数据供UI显示
]]
local function handle_sensor_data(temp, hum, air)
    -- 温度有效性验证函数
    local function is_valid_temp(v) return v and v > -40 and v < 100 end
    -- 湿度有效性验证函数
    local function is_valid_hum(v)  return v and v >= 0 and v <= 100 end
    -- 空气质量有效性验证函数
    local function is_valid_air(v)  return v and v >= 0 and v < 5000 end

    if is_valid_temp(temp) then
        -- 存入历史图表前向下取整，适配AirUI折线图不支持小数的问题
        local temp_int = math.floor(temp)
        table.insert(history.temperature, temp_int)
        if #history.temperature > MAX_HISTORY then table.remove(history.temperature, 1) end
        log.info("status_provider", "temperature history stored", temp, "->", temp_int)
    end
    if is_valid_hum(hum) then
        -- 存入历史图表前向下取整，适配AirUI折线图不支持小数的问题
        local hum_int = math.floor(hum)
        table.insert(history.humidity, hum_int)
        if #history.humidity > MAX_HISTORY then table.remove(history.humidity, 1) end
        log.info("status_provider", "humidity history stored", hum, "->", hum_int)
    end
    if is_valid_air(air) then
        -- 空气质量已经是整数，直接存储
        table.insert(history.air, air)
        if #history.air > MAX_HISTORY then table.remove(history.air, 1) end
    end
    sys.publish("STATUS_SENSOR_UPDATED", temp, hum, air)  -- 仍发布原始值用于UI显示
end

--[[
获取当前时间接口

@function StatusProvider.get_time
@summary 获取当前时间字符串
@return string 当前时间，格式为"HH:MM"

@usage
-- 调用示例：
-- local time_str = StatusProvider.get_time()
-- print("当前时间:", time_str)
]]
function StatusProvider.get_time()
    return current_time
end
--[[
获取信号等级接口

@function StatusProvider.get_signal_level
@summary 获取当前信号强度等级
@return number 信号等级，范围：-1（无SIM卡），1-5（信号等级，1最差，5最好）

@usage
-- 调用示例：
-- local signal_level = StatusProvider.get_signal_level()
-- if signal_level == -1 then
--     print("无SIM卡")
-- else
--     print("信号等级:", signal_level)
-- end
]]
function StatusProvider.get_signal_level()
    return csq_level
end
--[[
获取最新传感器数据接口

@function StatusProvider.get_sensor_latest
@summary 获取最新的传感器数据
@return number|nil 最新温度值（摄氏度），无数据时返回nil
@return number|nil 最新湿度值（百分比），无数据时返回nil
@return number|nil 最新空气质量值（整数），无数据时返回nil

@usage
-- 调用示例：
-- local temp, hum, air = StatusProvider.get_sensor_latest()
-- if temp then
--     print("温度:", temp, "℃")
-- end
-- if hum then
--     print("湿度:", hum, "%")
-- end
-- if air then
--     print("空气质量:", air)
-- end
]]
function StatusProvider.get_sensor_latest()
    local t = history.temperature[#history.temperature]
    local h = history.humidity[#history.humidity]
    local a = history.air[#history.air]
    return t, h, a
end
--[[
获取传感器历史数据接口

@function StatusProvider.get_history
@summary 获取指定传感器的历史数据数组
@param sensor_type string 传感器类型，可选值："temperature"（温度）、"humidity"（湿度）、"air"（空气质量）
@return table 传感器历史数据数组，无数据时返回空表

@usage
-- 调用示例：
-- local temp_history = StatusProvider.get_history("temperature")
-- for i, temp in ipairs(temp_history) do
--     print("历史温度", i, ":", temp, "℃")
-- end
]]
function StatusProvider.get_history(sensor_type)
    return history[sensor_type] or {}
end

--[[
模块初始化函数，在模块加载时自动执行

@local
@function init
@summary 初始化状态提供器模块，设置定时器和事件订阅
@return nil

@usage
-- 模块加载时自动调用，执行以下初始化操作：
-- 1、启动每秒更新时间定时器
-- 2、启动每2秒更新信号定时器
-- 3、订阅SIM卡状态变化事件
-- 4、订阅传感器数据更新事件
-- 5、立即执行一次时间更新和信号更新
]]
local function init()
    sys.timerLoopStart(update_time, 1000)
    sys.timerLoopStart(update_signal, 2000)
    sys.subscribe("SIM_IND", handle_sim_ind)
    sys.subscribe("ui_sensor_data", handle_sensor_data)
    update_time()
    update_signal()
end
init()

return StatusProvider