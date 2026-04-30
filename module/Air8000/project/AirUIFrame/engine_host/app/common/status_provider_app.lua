--[[
@module  status_provider_app
@summary 状态提供器应用模块，负责收集和管理系统状态信息
@version 1.1
@date    2026.03.26
@author  江访
@usage
本模块为状态提供器应用模块，主要功能包括：
1、管理时间信息，每秒更新当前时间、日期、星期；
2、管理WiFi信号强度，根据连接状态和RSSI动态更新信号等级；
3、提供状态查询接口供其他模块调用；
4、发布状态更新事件供UI系统响应；

对外接口：
1、StatusProvider.get_time()：获取当前时间（HH:MM）
2、StatusProvider.get_date()：获取当前日期（YYYY-MM-DD）
3、StatusProvider.get_weekday()：获取当前星期几（中文）
4、StatusProvider.get_signal_level()：获取4G信号等级（-1或1-5）
5、StatusProvider.get_wifi_signal_level()：获取WiFi信号等级（0-4）
]]

-- 当前时间字符串，格式为"HH:MM"
local current_time = "08:00"
-- 当前日期字符串，格式为"YYYY-MM-DD"
local current_date = "1970-01-01"
-- 当前星期字符串，中文
local current_weekday = "星期四"

-- WiFi信号相关变量
local wifi_connected = false
local wifi_signal_level = 0
local wifi_rssi = nil
local wifi_timer = nil

-- 星期映射表（从英文星期到中文）
local weekday_map = {
    ["Sunday"] = "星期日",
    ["Monday"] = "星期一",
    ["Tuesday"] = "星期二",
    ["Wednesday"] = "星期三",
    ["Thursday"] = "星期四",
    ["Friday"] = "星期五",
    ["Saturday"] = "星期六",
}

-- 更新时间、日期、星期
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        current_time = string.format("%02d:%02d", dt.hour, dt.min)
        -- 注意：os.date("*t") 返回的月份字段是 month，不是 mon
        current_date = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
        -- 获取英文星期全名，再转为中文
        local en_weekday = os.date("%A", t)
        current_weekday = weekday_map[en_weekday] or en_weekday
        -- 发布时间更新事件
        sys.publish("STATUS_TIME_UPDATED", current_time, current_date, current_weekday)
    end
end

-- 根据RSSI计算信号等级（0-4）
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

-- 更新WiFi信号等级
local function update_wifi_signal()
    if not wifi_connected then
        if wifi_signal_level ~= 0 then
            wifi_signal_level = 0
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        end
        return
    end

    local info = wlan.getInfo()
    if info and info.rssi then
        wifi_rssi = info.rssi
        local new_level = rssi_to_level(wifi_rssi)
        if wifi_signal_level ~= new_level then
            wifi_signal_level = new_level
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        end
    else
        log.warn("status_provider", "Failed to get WiFi RSSI")
    end
end

-- WiFi STA事件处理
local function sta_event(evt, data)
    log.info("status_provider", "WLAN_STA_INC", evt, data)
    if evt == "CONNECTED" then
        wifi_connected = true
        wifi_signal_level = 3
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        update_wifi_signal()
        if wifi_timer then
            sys.timerStop(update_wifi_signal)
        end
        wifi_timer = sys.timerLoopStart(update_wifi_signal, 1000)
    elseif evt == "DISCONNECTED" then
        wifi_connected = false
        if wifi_timer then
            sys.timerStop(update_wifi_signal)
            wifi_timer = nil
        end
        if wifi_signal_level ~= 0 then
            wifi_signal_level = 0
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        end
    end
end

-- 获取当前时间
local function get_time()
    return current_time
end

-- 获取当前日期
local function get_date()
    return current_date
end

-- 获取当前星期几（中文）
local function get_weekday()
    return current_weekday
end

local function get_wifi_signal_level()
    return wifi_signal_level
end

-- 4G/移动信号相关变量
local mobile_signal_level = -1
local sim_present = false
local mobile_timer = nil

if rtos.bsp() ~= "Air8101" and rtos.bsp() ~= "PC" and rtos.bsp() ~= "Air1601" and rtos.bsp() ~= "Air1602" then
    -- 开启SIM暂时脱离后自动恢复，30秒搜索一次周围小区信息，会增加功耗
    mobile.setAuto(10000, 30000, 5) -- 此函数仅需配置一次
end

local function update_mobile_signal()
     local old_level = mobile_signal_level
    if not sim_present then
        mobile_signal_level = -1
        log.info("status_provider", "no sim, set level -1")
    else
        local csq = mobile.csq()
        -- log.info("status_provider", "csq raw =", csq)
        if csq == 99 or csq <= 5 then
            mobile_signal_level = 1
        elseif csq <= 10 then
            mobile_signal_level = 2
        elseif csq <= 15 then
            mobile_signal_level = 3
        elseif csq <= 20 then
            mobile_signal_level = 4
        else
            mobile_signal_level = 5
        end
        log.info("status_provider", "mapped level =", mobile_signal_level)
    end
    if old_level ~= mobile_signal_level then
        sys.publish("STATUS_SIGNAL_UPDATED", mobile_signal_level)
    end
end

local function handle_sim_ind(status, value)
    log.info("status_provider", "SIM_IND", status, value or "")
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" then
        sim_present = false
    end
    update_mobile_signal()
end

local function get_signal_level()
    return mobile_signal_level
end

-- 获取最新传感器数据（保留接口，返回nil）
local function get_sensor_latest()
    return nil, nil, nil
end

-- 获取传感器历史数据（保留接口，返回空表）
local function get_history(sensor_type)
    return {}
end

local function init()
    sys.timerLoopStart(update_time, 1000)
    sys.subscribe("WLAN_STA_INC", sta_event)
    sys.subscribe("SIM_IND", handle_sim_ind)
    update_time()

    if rtos.bsp() == "PC" then
        sim_present = true
    elseif rtos.bsp() ~= "Air8101" then
        sim_present = mobile.simPin() or false
    else
        sim_present = mobile.simPin() or false
        local info = wlan.getInfo()
        if info and info.ssid then
            wifi_connected = true
            update_wifi_signal()
            wifi_timer = sys.timerLoopStart(update_wifi_signal, 1000)
        else
            wifi_connected = false
            wifi_signal_level = 0
        end
    end

    mobile_timer = sys.timerLoopStart(update_mobile_signal, 2000)
    update_mobile_signal()

    sys.subscribe("REQUEST_STATUS_REFRESH", function()
        sys.publish("STATUS_TIME_UPDATED", current_time, current_date, current_weekday)
        sys.publish("STATUS_SIGNAL_UPDATED", mobile_signal_level)
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
    end)
end
init()