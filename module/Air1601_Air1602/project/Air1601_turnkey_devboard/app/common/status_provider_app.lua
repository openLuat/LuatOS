-- status_provider_app.lua
local StatusProvider = {}
local history = {
    temperature = {},
    humidity    = {},
    air         = {}
}
local MAX_HISTORY = 20
local csq_level = -1
local sim_present = false
local current_time = "08:00"
local mobile_auto = false
local air780_time = nil -- 存储从Air780EPM收到的时间

-- 加载 airlink_mobile_info 模块
local airlink_mobile_info = require "airlink_mobile_info"

-- 更新时间
local function update_time()
    if air780_time then
        -- 使用从Air780EPM收到的时间
        local dt = air780_time
        current_time = string.format("%02d:%02d", dt.hour, dt.min)
        local current_date = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
        sys.publish("STATUS_TIME_UPDATED", current_time)
        sys.publish("STATUS_DATE_UPDATED", current_date)
    else
        -- 回退到系统时间
        local t = os.time()
        if t then
            local dt = os.date("*t", t)
            current_time = string.format("%02d:%02d", dt.hour, dt.min)
            local current_date = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
            sys.publish("STATUS_TIME_UPDATED", current_time)
            sys.publish("STATUS_DATE_UPDATED", current_date)
        end
    end
end

-- 更新信号等级和mobile_auto（带日志）
local function update_signal()
    local old_level = csq_level
    local old_auto = mobile_auto
    if rtos.bsp() == "Air1601" then
        -- Air1601 是 MCU 模组，使用 airlink_mobile_info 获取 Air780EPM 的 csq
        local csq = airlink_mobile_info.get_csq()
        local auto = airlink_mobile_info.get_auto()
        log.info("status_provider", "csq from Air780EPM =", csq)
        if csq and csq >= 0 then
            if csq == 99 or csq <= 5 then
                csq_level = 5  -- 感叹号，信号不好
            elseif csq <= 10 then
                csq_level = 1  -- 1格信号
            elseif csq <= 15 then
                csq_level = 2  -- 2格信号
            elseif csq <= 20 then
                csq_level = 3  -- 3格信号
            else
                csq_level = 4  -- 4格信号，信号最好
            end
            log.info("status_provider", "mapped level =", csq_level)
        else
            csq_level = -1  -- 未获取到 csq 信息
            log.info("status_provider", "no csq info, set level -1")
        end
        -- 更新mobile_auto
        if auto ~= nil then
            mobile_auto = auto
        end
    elseif not sim_present then
        csq_level = -1
        log.info("status_provider", "no sim, set level -1")
    else
        local csq = mobile.csq()
        log.info("status_provider", "csq raw =", csq)
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
        log.info("status_provider", "mapped level =", csq_level)
    end
    if old_level ~= csq_level then
        log.info("status_provider", "signal level changed from", old_level, "to", csq_level)
        sys.publish("STATUS_SIGNAL_UPDATED", csq_level)
    end
    if old_auto ~= mobile_auto then
        sys.publish("STATUS_MOBILE_AUTO_UPDATED", mobile_auto)
    end
end

-- SIM卡状态处理（增加日志）
local function handle_sim_ind(status, value)
    log.info("status_provider", "SIM_IND", status, value or "")
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" then
        sim_present = false
    end
    update_signal()  -- 立即更新一次
end

-- 传感器数据更新（增加有效性过滤）
local function handle_sensor_data(temp, hum, air)
    local function is_valid_temp(v) return v and v > -40 and v < 100 end
    local function is_valid_hum(v)  return v and v >= 0 and v <= 100 end
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

-- 公开接口
function StatusProvider.get_time()
    return current_time
end
function StatusProvider.get_signal_level()
    return csq_level
end
function StatusProvider.get_sensor_latest()
    local t = history.temperature[#history.temperature]
    local h = history.humidity[#history.humidity]
    local a = history.air[#history.air]
    return t, h, a
end
function StatusProvider.get_history(sensor_type)
    return history[sensor_type] or {}
end

function StatusProvider.get_mobile_auto()
    return mobile_auto
end

-- 处理Air780EPM时间更新事件
local function handle_air780_time_updated(time_info)
    air780_time = time_info
    log.info("status_provider", "从Air780EPM更新时间", time_info.year, time_info.month, time_info.day, time_info.hour, time_info.min, time_info.sec)
    update_time() -- 立即更新时间显示
end

-- 处理Air780EPM mobile信息更新事件
local function handle_airlink_mobile_info_updated(info)
    log.info("status_provider", "收到AIRLINK_MOBILE_INFO_UPDATED事件")
    update_signal() -- 立即更新信号
end

-- 初始化
local function init()
    sys.timerLoopStart(update_time, 1000)
    sys.timerLoopStart(update_signal, 2000)
    sys.subscribe("SIM_IND", handle_sim_ind)
    sys.subscribe("ui_sensor_data", handle_sensor_data)
    sys.subscribe("AIR780_TIME_UPDATED", handle_air780_time_updated)
    sys.subscribe("AIRLINK_MOBILE_INFO_UPDATED", handle_airlink_mobile_info_updated)
    update_time()
    update_signal()
end
init()

return StatusProvider