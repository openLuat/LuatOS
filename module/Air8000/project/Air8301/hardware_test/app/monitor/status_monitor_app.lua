--[[
@module  status_monitor_app
@summary 状态监控与告警模块
@version 1.0
@date    2026.09.04
@author  江访
@usage
监控内存(Lua堆)/Flash(文件系统)/运行时间，告警系统(cooldown去重、最多50条、自动MQTT发布)。
与UI层通过发布/订阅机制通信。
]]

local TASK_NAME = "status_monitor"

-- 内存状态
local memory_total = 0
local memory_used = 0
local memory_max_used = 0
local memory_usage_percent = 0

-- Flash状态(缓存，避免频繁SPI访问导致总线冲突)
local flash_total = 0
local flash_used = 0
local flash_usage_percent = 0
local flash_last_query_time = 0
local FLASH_QUERY_MIN_INTERVAL = 30000 -- Flash查询最小间隔30ms，避免SPI总线冲突

-- 运行时间
local runtime_sec = 0
local runtime_str = ""

-- 告警相关
local MAX_ALARM_COUNT = 50
local alarm_list = {}
local ALARM_COOLDOWN_SEC = 10
local alarm_last_trigger_time = {}

-- 定时器
local status_timer = nil

--[[
@function format_runtime
@summary 格式化运行时间为天时分秒
@param sec number 运行时间（秒）
@return string 格式化后的运行时间字符串
]]
local function format_runtime(sec)
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    local minutes = math.floor((sec % 3600) / 60)
    local seconds = sec % 60

    if days > 0 then
        return string.format("%dd%dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh%dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm%ds", minutes, seconds)
    else
        return string.format("%ds", seconds)
    end
end

local function format_runtime_full(sec)
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    local minutes = math.floor((sec % 3600) / 60)
    local seconds = sec % 60

    if days > 0 then
        return string.format("%d天 %02d时 %02d分 %02d秒", days, hours, minutes, seconds)
    else
        return string.format("%02d时 %02d分 %02d秒", hours, minutes, seconds)
    end
end

--[[
@function update_memory_info
@summary 更新内存信息
]]
local function update_memory_info()
    local total, used, max_used = rtos.meminfo("lua")
    if total and used and total > 0 then
        memory_total = total
        memory_used = used
        memory_max_used = max_used
        memory_usage_percent = math.floor((used / total) * 100 + 0.5)
        sys.publish("monitor_memory_update", {
            usage_percent = memory_usage_percent,
            total = total,
            used = used,
            max_used = max_used
        })
    end
end

--[[
@function update_flash_info
@summary 更新Flash信息(外部SPI Flash /flash，带缓存保护)
@description 查询 /flash 文件系统状态。缓存30ms避免频繁SPI访问导致总线冲突
(与双CH390以太网芯片共用SPI1)。
]]
local function update_flash_info()
    local now = os.time()
    if now - flash_last_query_time < FLASH_QUERY_MIN_INTERVAL and flash_total > 0 then
        return -- 使用缓存，避免短时间内重复访问SPI Flash
    end
    flash_last_query_time = now

    local success, total_blocks, used_blocks, block_size = io.fsstat("/flash")
    if success and total_blocks and used_blocks and block_size then
        flash_total = total_blocks * block_size
        flash_used = used_blocks * block_size
        if flash_total > 0 then
            flash_usage_percent = math.floor((flash_used / flash_total) * 100 + 0.5)
        end
        sys.publish("monitor_flash_update", {
            usage_percent = flash_usage_percent,
            total = flash_total,
            used = flash_used
        })
    end
end

--[[
@function update_runtime_info
@summary 更新运行时间信息
]]
local function update_runtime_info()
    local sec_h, sec_l = mcu.ticks2(2)
    if sec_h and sec_l then
        runtime_sec = sec_h * 0x100000000 + sec_l
        runtime_str = format_runtime(runtime_sec)
        sys.publish("monitor_runtime_update", {
            runtime_sec = runtime_sec,
            runtime_str = runtime_str,
            runtime_full_str = format_runtime_full(runtime_sec)
        })
    end
end

--[[
@function update_status_info
@summary 更新内存和运行时间（定时器调用，不含Flash避免SPI总线冲突）
]]
local function update_status_info()
    update_memory_info()
    update_runtime_info()
end

--[[
@function add_alarm
@summary 添加告警
@param data table 告警数据 {type, message, level}
]]
local function add_alarm(data)
    local alarm_type = data.type

    -- 防抖：检查是否在冷却中
    local now = os.time()
    local last_time = alarm_last_trigger_time[alarm_type] or 0
    if now - last_time < ALARM_COOLDOWN_SEC then
        return
    end

    alarm_last_trigger_time[alarm_type] = now

    local alarm = {
        id = alarm_type .. "_" .. now,
        type = alarm_type,
        message = data.message,
        level = data.level or "warning",
        time = now
    }
    table.insert(alarm_list, 1, alarm)
    while #alarm_list > MAX_ALARM_COUNT do
        table.remove(alarm_list)
    end
    log.info(TASK_NAME, "alarm added", alarm.level, alarm.message)

    -- MQTT 上发告警
    if mobile and mobile.imei then
        local imei = mobile.imei()
        if imei then
            local topic = "device/" .. imei .. "/event"
            local event_data = {
                ts = now,
                type = "alarm",
                data = {
                    id = alarm.id,
                    level = alarm.level,
                    message = alarm.message
                }
            }
            sys.publish("SEND_DATA_REQ", TASK_NAME, topic, json.encode(event_data), 1)
        end
    end

    sys.publish("ALARM_UPDATE", {
        list = alarm_list,
        count = #alarm_list,
        max = MAX_ALARM_COUNT
    })
end

--[[
@function subscribe_events
@summary 订阅所有事件
]]
local function subscribe_events()
    -- 监控查询（页面打开时触发，含Flash查询）
    sys.subscribe("monitor_query", function()
        update_status_info()
        update_flash_info() -- Flash单独查询，避免定时器频繁访问SPI
        sys.publish("monitor_full_update", {
            memory_usage_percent = memory_usage_percent,
            memory_total = memory_total,
            memory_used = memory_used,
            memory_max_used = memory_max_used,
            flash_usage_percent = flash_usage_percent,
            flash_total = flash_total,
            flash_used = flash_used,
            runtime_str = runtime_str,
            runtime_full_str = format_runtime_full(runtime_sec),
        })
    end)

    -- 告警触发
    sys.subscribe("ALARM_TRIGGER", function(data)
        if data and data.type and data.message then
            add_alarm(data)
        end
    end)

    -- 清空告警
    sys.subscribe("ALARM_CLEAR_ALL", function()
        alarm_list = {}
        log.info(TASK_NAME, "alarms cleared")
        sys.publish("ALARM_UPDATE", {list = alarm_list, count = 0, max = MAX_ALARM_COUNT})
    end)

    -- 告警查询
    sys.subscribe("ALARM_QUERY", function()
        sys.publish("ALARM_UPDATE", {
            list = alarm_list,
            count = #alarm_list,
            max = MAX_ALARM_COUNT
        })
    end)
end

-- 初始化
subscribe_events()
update_status_info()
status_timer = sys.timerLoopStart(update_status_info, 2000)
log.info(TASK_NAME, "initialized")
