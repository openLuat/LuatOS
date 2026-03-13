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
local current_time = "--:--"

-- 更新时间
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        current_time = string.format("%02d:%02d", dt.hour, dt.min)
        sys.publish("STATUS_TIME_UPDATED", current_time)
    end
end

-- 更新信号等级（带日志）
local function update_signal()
    local old_level = csq_level
    if not sim_present then
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
        sys.publish("STATUS_SIGNAL_UPDATED", csq_level)
    end
end

-- SIM卡状态处理（增加日志）
local function handle_sim_ind(status, value)
    log.info("status_provider", "SIM_IND", status, value or "")
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" or status == "SIM NOT INSERTED" then
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
        table.insert(history.temperature, temp)
        if #history.temperature > MAX_HISTORY then table.remove(history.temperature, 1) end
    end
    if is_valid_hum(hum) then
        table.insert(history.humidity, hum)
        if #history.humidity > MAX_HISTORY then table.remove(history.humidity, 1) end
    end
    if is_valid_air(air) then
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

-- 初始化
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