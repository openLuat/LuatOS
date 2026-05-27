--[[
@module  status_provider_app
@summary 状态提供器应用模块，负责收集和管理系统状态信息
@version 1.2
@date    2026.05.19
@author  江访
@usage
本模块为状态提供器应用模块，主要功能包括：
1、管理时间信息，每秒更新当前时间、日期、星期；
2、管理WiFi信号强度，通过监听WIFI_CONNECTED/DISCONNECTED事件控制RSSI轮询；
3、提供状态查询接口供其他模块调用；
4、发布状态更新事件供UI系统响应；

== 设计原则 ==
WiFi 连接状态由 wifi_app 统一管理（监听 WLAN_STA_INC）。
status_provider 只负责 RSSI 信号强度轮询，通过 WIFI_CONNECTED/DISCONNECTED
控制轮询定时器的启停，不与 wifi_app 产生重复状态跟踪。

对外接口：
1、StatusProvider.get_time()：获取当前时间（HH:MM）
2、StatusProvider.get_date()：获取当前日期（YYYY-MM-DD）
3、StatusProvider.get_weekday()：获取当前星期几（中文）
4、StatusProvider.get_signal_level()：获取4G信号等级（-1或1-5，仅Air8000）
5、StatusProvider.get_wifi_signal_level()：获取WiFi信号等级（0-4）
]]

local has_4g = _G.project_config and _G.project_config.features and _G.project_config.features.net_4g
local has_wifi = _G.project_config and _G.project_config.features and _G.project_config.features.wifi

local current_time = "08:00"
local current_date = "1970-01-01"
local current_weekday = "星期四"

local wifi_connected = false
local wifi_signal_level = 0
local wifi_rssi = nil
local wifi_timer = nil

local weekday_map = {
    ["Sunday"] = "星期日",
    ["Monday"] = "星期一",
    ["Tuesday"] = "星期二",
    ["Wednesday"] = "星期三",
    ["Thursday"] = "星期四",
    ["Friday"] = "星期五",
    ["Saturday"] = "星期六",
}

--[[
更新时间信息并发布STATUS_TIME_UPDATED事件
]]
local function update_time()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        current_time = string.format("%02d:%02d", dt.hour, dt.min)
        current_date = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
        local ew = os.date("%A", t)
        current_weekday = weekday_map[ew] or ew
        sys.publish("STATUS_TIME_UPDATED", current_time, current_date, current_weekday)
    end
end

--[[
RSSI信号强度转等级
@param number rssi - 信号强度值
@return number level - 信号等级（0-4）
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
更新WiFi信号强度
仅当wifi_connected为true时轮询RSSI并发布STATUS_WIFI_SIGNAL_UPDATED事件
]]
local function update_wifi_signal()
    if not wifi_connected then
        -- 未连接时确保图标显示为0
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
        -- 已连接但无法获取RSSI（IP尚未就绪），保持"正在获取IP"状态
        if wifi_signal_level ~= 5 then
            wifi_signal_level = 5
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        end
    end
end

--[[
处理WIFI_CONNECTED事件（由wifi_app发布）
连接成功后启动RSSI轮询定时器
@param string ssid - 连接的SSID
]]
local function handle_wifi_connected(ssid)
    log.info("status_provider", "WiFi已连接:", ssid)
    wifi_connected = true
    -- L2已连接AP但IP尚未获取，发布level=5显示"正在获取IP"图标
    -- IP_READY后会启动RSSI轮询，届时更新为真实信号等级0-4
    wifi_signal_level = 5
    sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
end

local function handle_ip_ready()
    log.info("status_provider", "IP已就绪，启动RSSI轮询")
    -- IP就绪后才开始RSSI轮询（每秒更新一次）
    if wifi_timer then
        sys.timerStop(wifi_timer)
        wifi_timer = nil
    end
    wifi_timer = sys.timerLoopStart(update_wifi_signal, 1000)
    -- 立即刷新一次
    update_wifi_signal()
end

--[[
处理WIFI_DISCONNECTED事件（由wifi_app发布）
断开连接后停止RSSI轮询，图标归零
]]
local function handle_wifi_disconnected(reason, code)
    log.info("status_provider", "WiFi已断开:", reason, code)
    wifi_connected = false

    -- 停止RSSI轮询
    if wifi_timer then
        sys.timerStop(wifi_timer)
        wifi_timer = nil
    end

    -- 图标归零
    if wifi_signal_level ~= 0 then
        wifi_signal_level = 0
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
    end
end

-- 对外接口
local function get_time()
    return current_time
end

local function get_date()
    return current_date
end

local function get_weekday()
    return current_weekday
end

local function get_wifi_signal_level()
    return wifi_signal_level
end

-- 4G移动网络信号部分（仅Air8000）
local mobile_signal_level = -1
local sim_present = false
local mobile_timer = nil

if has_4g then
    pcall(mobile.setAuto, 10000, 30000, 5)
end

local function update_mobile_signal()
    local old_level = mobile_signal_level
    if not sim_present then
        mobile_signal_level = -1
        log.info("status_provider", "无SIM卡，信号等级=-1")
    else
        local ok, csq = pcall(mobile.csq)
        if not ok then csq = 99 end
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
    end
    if old_level ~= mobile_signal_level then
        sys.publish("STATUS_SIGNAL_UPDATED", mobile_signal_level)
    end
end

local function handle_sim_ind(st, vl)
    log.info("status_provider", "SIM_IND", st, vl or "")
    if st == "RDY" then
        sim_present = true
    elseif st == "NORDY" then
        sim_present = false
    end
    update_mobile_signal()
end

local function get_signal_level()
    return mobile_signal_level
end

local function get_sensor_latest()
    return nil, nil, nil
end

local function get_history(st)
    return {}
end

--[[
模块初始化
]]
local function init_module()
    -- 时间更新（每秒）
    sys.timerLoopStart(update_time, 1000)
    update_time()

    -- 订阅WiFi连接/断开事件（由wifi_app发布），替代直接监听WLAN_STA_INC
    -- 这样wifi_app是WLAN_STA_INC的唯一消费者，状态管理清晰
    if has_wifi then
        sys.subscribe("WIFI_CONNECTED", handle_wifi_connected)
        sys.subscribe("WIFI_DISCONNECTED", handle_wifi_disconnected)
        sys.subscribe("IP_READY", handle_ip_ready)
    end

    -- 有4G模块
    if has_4g then
        sys.subscribe("SIM_IND", handle_sim_ind)
        if _G.project_config and _G.project_config.chip == "PC" then
            sim_present = true
        else
            local ok, pin = pcall(mobile.simPin)
            sim_present = ok and pin or false
        end
        mobile_timer = sys.timerLoopStart(update_mobile_signal, 2000)
        update_mobile_signal()
        sys.subscribe("REQUEST_STATUS_REFRESH", function()
            sys.publish("STATUS_TIME_UPDATED", current_time, current_date, current_weekday)
            sys.publish("STATUS_SIGNAL_UPDATED", mobile_signal_level)
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        end)
    elseif has_wifi then
        -- 非4G但有WiFi（Air1601/Air8101等）：启动时检查是否已有连接
        if _G.project_config and _G.project_config.chip == "PC" then
            -- PC模拟器，不检测真实连接
        else
            local info = wlan.getInfo()
            if info and info.ssid then
                wifi_connected = true
                -- 先发布"正在获取IP"状态，RSSI轮询会在获取到信号后更新为真实等级
                wifi_signal_level = 5
                sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
                update_wifi_signal()
                wifi_timer = sys.timerLoopStart(update_wifi_signal, 1000)
            else
                wifi_connected = false
                wifi_signal_level = 0
            end
        end
        sys.subscribe("REQUEST_STATUS_REFRESH", function()
            sys.publish("STATUS_TIME_UPDATED", current_time, current_date, current_weekday)
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        end)
    end
end

init_module()
