-- Naming convention: local fns ≤5 chars, local vars ≤4 chars
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
4、StatusProvider.get_signal_level()：获取4G信号等级（-1或1-5，仅Air8000）
5、StatusProvider.get_wifi_signal_level()：获取WiFi信号等级（0-4）
6、StatusProvider.get_sensor_latest()：获取最新传感器数据（保留接口）
7、StatusProvider.get_history()：获取传感器历史数据（保留接口）
]]

local ia8 = _G.model_str:find("Air8000") ~= nil

local ct = "08:00"
local cd = "1970-01-01"
local cw = "星期四"

local wc = false
local wsl = 0
local wr = nil
local wt = nil

local weekday_map = {
    ["Sunday"] = "星期日",
    ["Monday"] = "星期一",
    ["Tuesday"] = "星期二",
    ["Wednesday"] = "星期三",
    ["Thursday"] = "星期四",
    ["Friday"] = "星期五",
    ["Saturday"] = "星期六",
}

local function uptm()
    local t = os.time()
    if t then
        local dt = os.date("*t", t)
        ct = string.format("%02d:%02d", dt.hour, dt.min)
        cd = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
        local ew = os.date("%A", t)
        cw = weekday_map[ew] or ew
        sys.publish("STATUS_TIME_UPDATED", ct, cd, cw)
    end
end

local function r2l(rssi)
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

local function upws()
    if not wc then
        if wsl ~= 0 then
            wsl = 0
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wsl)
        end
        return
    end
    local info = wlan.getInfo()
    if info and info.rssi then
        wr = info.rssi
        local nl = r2l(wr)
        if wsl ~= nl then
            wsl = nl
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wsl)
        end
    else
        log.warn("stpr", "Failed to get WiFi RSSI")
    end
end

local function stev(ev, dt)
    log.info("stpr", "WLAN_STA_INC", ev, dt)
    if ev == "CONNECTED" then
        wc = true
        wsl = 3
        sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wsl)
        upws()
        if wt then
            sys.timerStop(upws)
        end
        wt = sys.timerLoopStart(upws, 1000)
    elseif ev == "DISCONNECTED" then
        wc = false
        if wt then
            sys.timerStop(upws)
            wt = nil
        end
        if wsl ~= 0 then
            wsl = 0
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wsl)
        end
    end
end

local function get_time()
    return ct
end

local function get_date()
    return cd
end

local function get_weekday()
    return cw
end

local function get_wifi_signal_level()
    return wsl
end

local msl = -1
local sp = false
local mt = nil

if ia8 then
    mobile.setAuto(10000, 30000, 5)
end

local function upms()
     local ol = msl
    if not sp then
        msl = -1
        log.info("stpr", "no sim, set level -1")
    else
        local csq = mobile.csq()
        if csq == 99 or csq <= 5 then
            msl = 1
        elseif csq <= 10 then
            msl = 2
        elseif csq <= 15 then
            msl = 3
        elseif csq <= 20 then
            msl = 4
        else
            msl = 5
        end
        log.info("stpr", "mapped level =", msl)
    end
    if ol ~= msl then
        sys.publish("STATUS_SIGNAL_UPDATED", msl)
    end
end

local function hsim(st, vl)
    log.info("stpr", "SIM_IND", st, vl or "")
    if st == "RDY" then
        sp = true
    elseif st == "NORDY" then
        sp = false
    end
    upms()
end

local function get_signal_level()
    return msl
end

local function get_sensor_latest()
    return nil, nil, nil
end

local function get_history(st)
    return {}
end

local function ini()
    sys.timerLoopStart(uptm, 1000)
    sys.subscribe("WLAN_STA_INC", stev)
    uptm()

    if ia8 then
        sys.subscribe("SIM_IND", hsim)
        if _G.model_str:find("PC") then
            sp = true
        else
            sp = mobile.simPin() or false
        end
        mt = sys.timerLoopStart(upms, 2000)
        upms()
        sys.subscribe("REQUEST_STATUS_REFRESH", function()
            sys.publish("STATUS_TIME_UPDATED", ct, cd, cw)
            sys.publish("STATUS_SIGNAL_UPDATED", msl)
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wsl)
        end)
    else
        if _G.model_str:find("PC") then
        else
            -- local info = wlan.getInfo()
            if info and info.ssid then
                wc = true
                upws()
                wt = sys.timerLoopStart(upws, 1000)
            else
                wc = false
                wsl = 0
            end
        end
        sys.subscribe("REQUEST_STATUS_REFRESH", function()
            sys.publish("STATUS_TIME_UPDATED", ct, cd, cw)
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wsl)
        end)
    end
end
ini()
