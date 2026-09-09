--[[
@module  sensor_app
@summary 传感器应用主模块（精简版，无UI）
@version 1.1
@date    2026.09.09
@author  江访
@usage
精简自 turnkey_devboard sensor_app，去除 ui_sensor_data 事件发布。
核心业务逻辑：
1、加载温湿度传感器驱动（AirSHT30_1000）和VOC传感器驱动（AirVOC_1000）；
2、启动传感器读取任务，默认每10秒读取一次数据（可通过云端远程修改）；
3、两个传感器均成功时发布"read_sht30_voc_rsp"供云端上报。
4、上报频率保存到 fskv，断电不丢失。
]]

-- 加载传感器驱动
local air_sht30 = require "AirSHT30_1000"
local air_voc = require "AirVOC_1000"

if rtos.bsp() ~= "Air8101" then
    -- 开启SIM暂时脱离后自动恢复，30秒搜索一次周围小区信息，会增加功耗
    mobile.setAuto(10000, 30000, 5)
end

-- ---- 上报频率配置 ----
local REPORT_CYCLE_KEY = "report_cycle"  -- fskv 存储 key
local DEFAULT_CYCLE = 10                 -- 默认上报频率（秒）
local MIN_CYCLE = 5                      -- 最小上报频率（秒）

-- 从 fskv 读取上报频率，不存在则用默认值
local function get_report_cycle()
    local val = fskv.get(REPORT_CYCLE_KEY)
    if val and type(val) == "number" and val >= MIN_CYCLE then
        return val
    end
    return DEFAULT_CYCLE
end

-- 保存上报频率到 fskv
local function set_report_cycle(seconds)
    if type(seconds) ~= "number" or seconds < MIN_CYCLE then
        return false
    end
    fskv.set(REPORT_CYCLE_KEY, seconds)
    log.info("sensor", "上报频率已保存: " .. seconds .. "秒")
    return true
end

-- 当前上报频率
local report_cycle = get_report_cycle()
log.info("sensor", "启动上报频率: " .. report_cycle .. "秒")

--[[
传感器读取任务（主循环）

@local
@function sensor_task
@return nil
@usage
-- 作为系统任务启动，循环等待"read_sensors_req"事件，每收到一次执行一次读取
-- 读取温湿度、VOC，两个传感器均成功时发布云端数据
]]
local function sensor_task()
    while true do
        -- 等待定时器发布的读取请求
        sys.waitUntil("read_sensors_req")

        local sht30_ok = false -- 温湿度本次读取成功标志
        local voc_ok = false   -- VOC本次读取成功标志
        local current_temp, current_hum, current_voc

        -- 1. 读取温湿度
        if air_sht30.open(1) then
            local t, h = air_sht30.read()
            if t then
                current_temp, current_hum = t, h
                sht30_ok = true
                log.info("sht30", string.format("温度:%.2f℃ 湿度:%.2f%%", t, h))
            else
                log.error("sht30", "read error")
            end
            air_sht30.close()
        else
            log.error("sht30", "open failed")
        end

        -- 2. 读取 VOC
        if air_voc.open(1) then
            local v = air_voc.get_ppb()
            if v then
                current_voc = v
                voc_ok = true
                log.info("voc", string.format("TVOC:%d ppb", v))
            else
                log.error("voc", "read error")
            end
            air_voc.close()
        else
            log.error("voc", "open failed")
        end

        -- 只有当两个传感器本次均成功读取时，才发布云端数据
        if sht30_ok and voc_ok then
            sys.publish("read_sht30_voc_rsp", current_temp, current_hum, current_voc)
            log.info("sensor", "两个传感器均成功，向云端发布更新数据请求")
        else
            log.info("sensor", "传感器读取不完整，跳过上报")
        end
    end
end

-- 启动传感器读取任务
sys.taskInit(sensor_task)

-- ---- 定时器管理（支持动态修改频率） ----
local report_timer = nil

local function start_report_timer()
    if report_timer then
        sys.timerStop(report_timer)
    end
    report_timer = sys.timerLoopStart(function()
        sys.publish("read_sensors_req")
    end, report_cycle * 1000)
    log.info("sensor", "定时器已启动，间隔 " .. report_cycle .. "秒")
end

-- 启动初始定时器
start_report_timer()

-- ---- 监听远程修改上报频率 ----
sys.subscribe("set_report_cycle", function(new_cycle)
    if type(new_cycle) ~= "number" or new_cycle < MIN_CYCLE then
        log.warn("sensor", "无效的上报频率: " .. tostring(new_cycle))
        return
    end
    report_cycle = new_cycle
    set_report_cycle(new_cycle)
    start_report_timer()
    log.info("sensor", "上报频率已更新为: " .. new_cycle .. "秒")
end)
