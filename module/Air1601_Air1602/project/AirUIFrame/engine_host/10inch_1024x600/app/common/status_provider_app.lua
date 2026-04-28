--[[
@module  status_provider_app
@summary 状态提供器应用模块，负责收集和管理系统状态信息
@version 1.1
@date    2026.04.16
@author  江访
@usage
本模块整合了三个原始版本的功能，已移除传感器数据获取相关代码。
主要功能：
1. 时间信息管理：支持系统时间和外部Air780EPM时间，提供时间(HH:MM)、日期(YYYY-MM-DD)、星期(中文)
2. WiFi信号管理：基于RSSI动态计算信号等级(0-4)，支持WiFi连接状态监听
3. 移动网络信号管理：基于CSQ动态计算信号等级(1-5)，支持SIM卡状态检测及Air1601桥接模式
4. 外部设备支持：接收Air780EPM的时间更新和移动网络信息，更新本地状态
5. 事件发布：状态变化时发布相应事件，供UI或其他模块响应

对外接口：
- StatusProvider.get_time()                 : 获取当前时间（HH:MM）
- StatusProvider.get_date()                 : 获取当前日期（YYYY-MM-DD）
- StatusProvider.get_weekday()              : 获取当前星期几（中文）
- StatusProvider.get_wifi_signal_level()    : 获取WiFi信号等级（0-4）
- StatusProvider.get_mobile_signal_level()  : 获取移动网络信号等级（-1无效，1-5）
- StatusProvider.get_signal_level()         : 获取主信号等级（移动网络，兼容旧版）
- StatusProvider.get_mobile_auto()          : 获取移动网络自动切换状态（布尔）
]]

local StatusProvider = {}

-- ========== 时间日期星期相关变量 ==========
local current_time = "08:00"       -- 格式 HH:MM
local current_date = "1970-01-01"  -- 格式 YYYY-MM-DD
local current_weekday = "星期四"    -- 中文星期
local air780_time = nil            -- 从Air780EPM收到的时间（优先级高于系统时间）

-- 星期映射表（英文 -> 中文）
local weekday_map = {
    ["Sunday"]    = "星期日",
    ["Monday"]    = "星期一",
    ["Tuesday"]   = "星期二",
    ["Wednesday"] = "星期三",
    ["Thursday"]  = "星期四",
    ["Friday"]    = "星期五",
    ["Saturday"]  = "星期六",
}

-- ========== WiFi信号相关变量 ==========
local wifi_connected = false        -- WiFi是否已连接
local wifi_signal_level = 0         -- WiFi信号等级 0-4
local wifi_rssi = nil               -- 当前RSSI值（dBm）
local wifi_timer = nil              -- WiFi更新定时器

-- ========== 移动网络信号相关变量 ==========
local csq_level = -1                -- 移动信号等级：-1无效，1-5（1最差，5最好）
local sim_present = false           -- SIM卡是否存在
local mobile_auto = false           -- 移动网络自动切换状态（仅Air1601桥接模式使用）

-- ========== 辅助函数 ==========

-- 根据RSSI计算WiFi信号等级（0-4）
local function rssi_to_wifi_level(rssi)
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

-- 更新WiFi信号等级（定时器回调）
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
        local new_level = rssi_to_wifi_level(wifi_rssi)
        if wifi_signal_level ~= new_level then
            wifi_signal_level = new_level
            sys.publish("STATUS_WIFI_SIGNAL_UPDATED", wifi_signal_level)
        end
    else
        log.warn("status_provider", "Failed to get WiFi RSSI")
    end
end

-- WiFi STA事件处理（连接/断开）
local function sta_event(evt, data)
    log.info("status_provider", "WLAN_STA_INC", evt, data)
    if evt == "CONNECTED" then
        wifi_connected = true
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

-- 根据原始CSQ值计算移动信号等级（1-5，-1表示无效）
local function raw_csq_to_mobile_level(csq)
    if csq == nil then
        return -1
    end
    if csq == 99 or csq <= 5 then
        return 5   -- 极差
    elseif csq <= 10 then
        return 1   -- 差
    elseif csq <= 15 then
        return 2   -- 一般
    elseif csq <= 20 then
        return 3   -- 好
    else
        return 4   -- 极好
    end
end

-- 更新移动网络信号等级和mobile_auto
local function update_mobile_signal()
    local old_level = csq_level
    local old_auto = mobile_auto

    -- 根据不同硬件平台采用不同策略
    if rtos.bsp() == "Air1601" then
        -- Air1601作为MCU，通过airlink_mobile_info获取Air780EPM的CSQ和auto状态
        local ok, airlink_mobile_info = pcall(require, "airlink_mobile_info")
        if ok then
            local csq = airlink_mobile_info.get_csq()
            local auto = airlink_mobile_info.get_auto()
            -- log.info("status_provider", "csq from Air780EPM =", csq)
            if csq and csq >= 0 then
                csq_level = raw_csq_to_mobile_level(csq)
                -- log.info("status_provider", "mapped mobile level =", csq_level)
            else
                csq_level = -1
                -- log.info("status_provider", "no csq info, set level -1")
            end
            if auto ~= nil then
                mobile_auto = auto
            end
        else
            -- log.warn("status_provider", "airlink_mobile_info not available")
            csq_level = -1
        end
    elseif not sim_present then
        csq_level = -1
        log.info("status_provider", "no sim, set level -1")
    else
        -- 普通移动网络设备（如Air780E等）
        local csq = mobile.csq()
        log.info("status_provider", "csq raw =", csq)
        csq_level = raw_csq_to_mobile_level(csq)
        -- log.info("status_provider", "mapped mobile level =", csq_level)
    end

    -- 信号等级变化时发布事件
    if old_level ~= csq_level then
        -- log.info("status_provider", "mobile signal level changed from", old_level, "to", csq_level)
        sys.publish("STATUS_MOBILE_SIGNAL_UPDATED", csq_level)
        -- 兼容旧版（主信号为移动信号）
        sys.publish("STATUS_SIGNAL_UPDATED", csq_level)
    end
    -- mobile_auto变化时发布事件
    if old_auto ~= mobile_auto then
        sys.publish("STATUS_MOBILE_AUTO_UPDATED", mobile_auto)
    end
end

-- SIM卡状态处理
local function handle_sim_ind(status, value)
    log.info("status_provider", "SIM_IND", status, value or "")
    if status == "RDY" then
        sim_present = true
    elseif status == "NORDY" then
        sim_present = false
    end
    update_mobile_signal()  -- 立即更新一次
end

-- 更新时间、日期、星期（优先使用外部Air780EPM时间，否则使用系统时间）
local function update_time()
    local t
    if air780_time then
        t = air780_time
        current_time = string.format("%02d:%02d", t.hour, t.min)
        current_date = string.format("%04d-%02d-%02d", t.year, t.month, t.day)
        -- 构建时间戳用于计算星期
        local timestamp = os.time({
            year = t.year, month = t.month, day = t.day,
            hour = t.hour, min = t.min, sec = t.sec or 0
        })
        local en_weekday = os.date("%A", timestamp)
        current_weekday = weekday_map[en_weekday] or en_weekday
    else
        local sys_t = os.time()
        if sys_t then
            local dt = os.date("*t", sys_t)
            current_time = string.format("%02d:%02d", dt.hour, dt.min)
            current_date = string.format("%04d-%02d-%02d", dt.year, dt.month, dt.day)
            local en_weekday = os.date("%A", sys_t)
            current_weekday = weekday_map[en_weekday] or en_weekday
        else
            -- 时间获取失败，保持原有值不更新
            return
        end
    end
    -- 发布各时间相关事件
    sys.publish("STATUS_TIME_UPDATED", current_time)
    sys.publish("STATUS_DATE_UPDATED", current_date)
    sys.publish("STATUS_WEEKDAY_UPDATED", current_weekday)
end

-- 处理Air780EPM时间更新事件
local function handle_air780_time_updated(time_info)
    air780_time = time_info
    -- log.info("status_provider", "从Air780EPM更新时间", time_info.year, time_info.month, time_info.day, time_info.hour, time_info.min, time_info.sec)
    update_time()
end

-- 处理Air780EPM mobile信息更新事件
local function handle_airlink_mobile_info_updated()
    -- log.info("status_provider", "收到AIRLINK_MOBILE_INFO_UPDATED事件")
    update_mobile_signal()
end

-- ========== 对外公开接口 ==========

-- 获取当前时间（HH:MM）
function StatusProvider.get_time()
    return current_time
end

-- 获取当前日期（YYYY-MM-DD）
function StatusProvider.get_date()
    return current_date
end

-- 获取当前星期几（中文）
function StatusProvider.get_weekday()
    return current_weekday
end

-- 获取WiFi信号等级（0-4）
function StatusProvider.get_wifi_signal_level()
    return wifi_signal_level
end

-- 获取移动网络信号等级（-1无效，1-5）
function StatusProvider.get_mobile_signal_level()
    return csq_level
end

-- 兼容旧版：主信号为移动网络信号
function StatusProvider.get_signal_level()
    return csq_level
end

-- 获取移动网络自动切换状态（仅Air1601桥接模式有效）
function StatusProvider.get_mobile_auto()
    return mobile_auto
end

-- ========== 模块初始化 ==========
local function init()
    -- 1. 时间定时器（每秒更新）
    sys.timerLoopStart(update_time, 1000)

    -- 2. 移动网络信号定时器（每2秒更新）
    sys.timerLoopStart(update_mobile_signal, 2000)

    -- 3. WiFi相关初始化（根据平台判断是否支持）
    local bsp = rtos.bsp()
    if bsp == "PC" then
        -- PC模拟环境，不做实际WiFi初始化
        -- log.info("status_provider", "Running on PC, WiFi disabled")
    elseif bsp == "Air8101" or bsp == "Air780E" or bsp == "Air101" then
        -- 支持WiFi的平台
        sys.subscribe("WLAN_STA_INC", sta_event)
        local info = wlan.getInfo()
        if info and info.ssid then
            wifi_connected = true
            update_wifi_signal()
            wifi_timer = sys.timerLoopStart(update_wifi_signal, 1000)
        else
            wifi_connected = false
            wifi_signal_level = 0
        end
    else
        -- 其他平台（如Air1601）通常不支持WiFi
        -- log.info("status_provider", "WiFi not supported on this BSP, skip")
    end

    -- 4. 订阅事件（已移除传感器相关订阅）
    sys.subscribe("SIM_IND", handle_sim_ind)                       -- SIM卡状态
    sys.subscribe("AIR780_TIME_UPDATED", handle_air780_time_updated)           -- 外部时间
    sys.subscribe("AIRLINK_MOBILE_INFO_UPDATED", handle_airlink_mobile_info_updated) -- 外部移动信息

    -- 5. 立即执行一次初始更新
    update_time()
    update_mobile_signal()
end

-- 启动初始化
init()

return StatusProvider