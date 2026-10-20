--[[
@module  sensor_app
@summary 传感器采集主模块（VOC + 485温湿度）
@version 1.2.0
@date    2026.10.16
@usage
定时读取 VOC 空气质量 + 485 温湿度，发布上报事件。

数据流向：
  定时器 → sys.publish("read_sensors_req") → sensor_task 读取传感器
  sensor_task → sys.publish("read_sensor_rsp", temp, hum, voc) → aircloud_app / ui

配置：
  DEFAULT_CYCLE: 默认上报频率（60 秒）
  MIN_CYCLE: 最小上报频率（5 秒）
  上报频率存 fskv，断电不丢失，云端 cycle:N 可改
]]

local air_voc = require "AirVOC_1000"
local modbus_th = require "modbus_th_drv"

-- V1.4 开发板 I2C1 总线电源：Camera(GPIO2) + ES8311(GPIO20)
-- 不打开这两个电源，I2C1 总线会被拉到地，导致 VOC 读不到
-- 注：GPIO23 是模组内部常高的 Vref，已由 main.lua 全局拉高，不在此处管理

if rtos.bsp() ~= "Air8101" then
    mobile.setAuto(10000, 30000, 5)
end

-- ---- 上报频率配置 ----
fskv.init()
local REPORT_CYCLE_KEY = "report_cycle"
local DEFAULT_CYCLE = 60
local MIN_CYCLE = 5

local function get_report_cycle()
    local val = fskv.get(REPORT_CYCLE_KEY)
    if val and type(val) == "number" and val >= MIN_CYCLE then
        return val
    end
    return DEFAULT_CYCLE
end

local function set_report_cycle(seconds)
    if type(seconds) ~= "number" or seconds < MIN_CYCLE then
        return false
    end
    fskv.set(REPORT_CYCLE_KEY, seconds)
    log.info("sensor", "上报频率已保存: " .. seconds .. "秒")
    return true
end

local report_cycle = get_report_cycle()
log.info("sensor", "启动上报频率: " .. report_cycle .. "秒")

local function sensor_task()
    -- 打开 I2C1 外设电源（Camera GPIO2 + ES8311 GPIO20），否则总线被拉低
    gpio.setup(2, 1)
    gpio.setup(20, 1)

    while true do
        sys.waitUntil("read_sensors_req")

        local current_temp, current_hum, current_voc

        -- 读取 VOC（I2C1）
        if air_voc.open(1) then
            local v = air_voc.get_ppb()
            if v then
                current_voc = v
                log.info("voc", string.format("TVOC:%d ppb", v))
            else
                log.error("voc", "read error")
            end
            air_voc.close()
        else
            log.error("voc", "open failed")
        end

        -- 读取 485 温湿度（Modbus RTU 主站）
        local t, h = modbus_th.read_temp_hum()
        if t then
            current_temp, current_hum = t, h
            log.info("modbus_th", string.format("温度:%.1f℃ 湿度:%.1f%%RH", t, h))
        end

        -- 无论成功与否都发布（nil 由 aircloud 端判断不上报）
        sys.publish("read_sensor_rsp", current_temp, current_hum, current_voc)
        log.info("sensor", "采集完成，temp=" .. tostring(current_temp)
                 .. " hum=" .. tostring(current_hum)
                 .. " voc=" .. tostring(current_voc))
    end
end

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

start_report_timer()

-- 监听云端修改上报频率
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
