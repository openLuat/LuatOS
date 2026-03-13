-- 加载传感器驱动
local air_sht30 = require "AirSHT30_1000"
local air_voc = require "AirVOC_1000"


-- 存储上一次的有效值
local last_temp = nil
local last_hum  = nil
local last_voc  = nil

if rtos.bsp() == "PC" then

elseif rtos.bsp() ~= "Air8101" then
    -- 开启SIM暂时脱离后自动恢复，30秒搜索一次周围小区信息，会增加功耗
    mobile.setAuto(10000, 30000, 5) -- 此函数仅需要配置一次
end


-- 传感器读取任务（主循环）
local function sensor_task()
    while true do
        -- 等待定时器发布的读取请求（每30秒一次）
        sys.waitUntil("read_sensors_req")

        local sht30_ok = false -- 温湿度本次读取成功标志
        local voc_ok = false   -- VOC本次读取成功标志
        local current_temp, current_hum, current_voc

        -- 1. 读取温湿度
        if air_sht30.open(0) then
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
        if air_voc.open(0) then
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

        -- 发布UI数据（无论成功与否，失败时对应值为nil）
        sys.publish("ui_sensor_data", current_temp, current_hum, current_voc)

        -- 只有当两个传感器本次均成功读取时，才发布云端数据并更新 last 值
        if sht30_ok and voc_ok then
            last_temp, last_hum, last_voc = current_temp, current_hum, current_voc
            sys.publish("read_sht30_voc_rsp", current_temp, current_hum, current_voc)
            log.info("sensor", "两个传感器均成功，向云端发布更新数据请求")
        else
            log.info("sensor", "传感器读取不完整，仅更新UI")
        end
    end
end

-- 启动传感器读取任务
sys.taskInit(sensor_task)

-- 每30秒触发一次读取请求（可根据需要调整周期）
sys.timerLoopStart(function()
    sys.publish("read_sensors_req")
end, 30000)
