-- 加载传感器驱动
local air_sht30 = require "AirSHT30_1000"
local air_voc = require "AirVOC_1000"


-- 存储上一次的有效值
local last_temp = nil
local last_hum  = nil
local last_voc  = nil

-- Air1601使用软件I2C1读取SHT30传感器
-- 软件I2C: SCL=GPIO14, SDA=GPIO8
local soft_i2c_port = nil

if rtos.bsp() == "Air1601" then
    -- 创建软件I2C1，使用GPIO14(SCL)和GPIO8(SDA)
    soft_i2c_port = i2c.createSoft(14, 8)
    log.info("sensor", "创建软件I2C1: SCL=GPIO14, SDA=GPIO8")
end

if rtos.bsp() == "PC" then

elseif rtos.bsp() ~= "Air8101" and rtos.bsp() ~= "Air1601" then
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

        -- 1. 读取温湿度（Air1601使用软件I2C1，其他平台使用硬件I2C）
        if rtos.bsp() == "Air1601" and soft_i2c_port then
            -- 使用软件I2C读取SHT30
            local slave_addr = 0x44
            -- 发送启动测量命令（高精度）
            i2c.send(soft_i2c_port, slave_addr, {0x24, 0x00})
            -- 等待测量完成
            sys.wait(20)
            -- 读取6字节数据
            local data = i2c.recv(soft_i2c_port, slave_addr, 6)
            if type(data) == "string" and data:len() == 6 then
                -- CRC校验和数据转换
                local temp_raw = (data:byte(1) << 8) | data:byte(2)
                local hum_raw = (data:byte(4) << 8) | data:byte(5)
                current_temp = -45 + 175 * temp_raw / 65535.0
                current_hum = 100 * hum_raw / 65535.0
                sht30_ok = true
                log.info("sht30", string.format("温度:%.2f℃ 湿度:%.2f%%", current_temp, current_hum))
            else
                log.error("sht30", "read error")
            end
        else
            -- 使用硬件I2C读取SHT30
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
        end

        -- 2. 读取 VOC（Air1601使用软件I2C1，其他平台使用硬件I2C）
        if rtos.bsp() == "Air1601" and soft_i2c_port then
            -- 使用软件I2C读取VOC传感器
            local slave_addr = 0x1A
            local reg_addr = 0x00
            local data_len = 5
            -- 发送寄存器地址
            i2c.send(soft_i2c_port, slave_addr, reg_addr)
            -- 等待数据准备
            sys.wait(20)
            -- 读取数据
            local data = i2c.recv(soft_i2c_port, slave_addr, data_len)
            if type(data) == "string" and data:len() == data_len then
                -- 计算CRC校验
                local function crc8(data)
                    local crc = 0xFF
                    for i = 1, #data do
                        crc = bit.bxor(crc, data[i])
                        for j = 1, 8 do
                            crc = crc * 2
                            if crc >= 0x100 then
                                crc = bit.band(bit.bxor(crc, 0x31), 0xff)
                            end
                        end
                    end
                    return crc
                end
                -- 检查校验值
                if crc8({data:byte(1), data:byte(2), data:byte(3), data:byte(4)}) == data:byte(5) then
                    -- 解析数据: 大端格式
                    current_voc = (data:byte(2) << 16) | (data:byte(3) << 8) | data:byte(4)
                    voc_ok = true
                    log.info("voc", string.format("TVOC:%d ppb", current_voc))
                else
                    log.error("voc", "crc error")
                end
            else
                log.error("voc", "read error")
            end
        else
            -- 使用硬件I2C读取VOC
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
        end

        -- 发布UI数据（无论成功与否，失败时对应值为nil）
        sys.publish("ui_sensor_data", current_temp, current_hum, current_voc)

        -- 只有当两个传感器本次均成功读取时，才发布云端数据并更新 last 值
        if sht30_ok and voc_ok then
            last_temp, last_hum, last_voc = current_temp, current_hum, current_voc
            sys.publish("read_sht30_voc_rsp", current_temp, current_hum, current_voc)
            log.info("sensor", "两个传感器均成功，向云端发布更新数据请求")
            
            -- 通过系统事件发送传感器数据给780EPM
            if rtos.bsp() == "Air1601" then
                local sensor_data = string.format("SENSOR_DATA:temp=%.2f,hum=%.2f,voc=%.0f", current_temp, current_hum, current_voc)
                log.info("sensor", "发送传感器数据给780EPM:", sensor_data)
                sys.publish("SENSOR_DATA_TO_AIR780", sensor_data)
            end
        else
            log.info("sensor", "传感器读取不完整，仅更新UI")
        end
    end
end

-- 启动传感器读取任务
sys.taskInit(sensor_task)

-- 每5秒触发一次读取请求（可根据需要调整周期）
sys.timerLoopStart(function()
    sys.publish("read_sensors_req")
end, 5000)
