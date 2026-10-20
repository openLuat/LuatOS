-- 加载传感器驱动
local air_sht30 = require "AirSHT30_1000"
local air_voc = require "AirVOC_1000"

-- 存储上一次的有效值
local last_temp = nil
local last_hum  = nil
local last_voc  = nil

-- ==================== I2C 模式选择 ====================
-- true  = 使用硬件 I2C1 (GPIO38=SDA, GPIO39=SCL)   【推荐】
-- false = 使用软件 I2C1 (GPIO14=SCL, GPIO8=SDA)
local USE_HARDWARE_I2C = true   -- 根据需要修改此处
-- ====================================================

-- 根据 Air1601 或其他平台做适配
if rtos.bsp() == "PC" then
    -- PC 模拟环境，不做特殊处理
elseif rtos.bsp() ~= "Air8101" and rtos.bsp() ~= "Air1601" then
    -- 非上述硬件平台，开启 SIM 脱离后自动恢复（仅需配置一次）
    mobile.setAuto(10000, 30000, 5)
end

-- 传感器读取任务（主循环）
local function sensor_task()
    local i2c_port = nil   -- 最终使用的 I2C 端口（硬件ID或软件对象）

    if rtos.bsp() == "Air1601" then
        if USE_HARDWARE_I2C then
            -- ---------- 硬件 I2C1 (GPIO38=SDA, GPIO39=SCL) ----------
            i2c_port = 1   -- 硬件 I2C1 的 ID
            if i2c.setup(i2c_port, i2c.FAST) ~= 1 then
                log.error("sensor", "硬件 I2C1 初始化失败，请检查引脚是否被占用或上拉电阻")
                return
            end
            log.info("sensor", "使用硬件 I2C1: SDA=GPIO38, SCL=GPIO39")
        else
            -- ---------- 软件 I2C1 (GPIO14=SCL, GPIO8=SDA) ----------
            i2c_port = i2c.createSoft(14, 8)   -- 返回软件 I2C 对象
            log.info("sensor", "使用软件 I2C1: SCL=GPIO14, SDA=GPIO8")
        end

        -- 打开两个传感器（传入正确的 I2C 端口）
        if not air_voc.open(i2c_port) then
            log.error("sensor", "AirVOC_1000 初始化失败")
        end
        if not air_sht30.open(i2c_port) then
            log.error("sensor", "AirSHT30_1000 初始化失败")
        end
    else
        -- 非 Air1601 平台（例如 Air8101 或其他），使用硬件 I2C0
        i2c_port = 0
        if i2c.setup(i2c_port, i2c.FAST) ~= 1 then
            log.error("sensor", "硬件 I2C0 初始化失败")
            return
        end
        log.info("sensor", "使用硬件 I2C0 (默认引脚)")
        if not air_voc.open(i2c_port) then
            log.error("sensor", "AirVOC_1000 初始化失败")
        end
        if not air_sht30.open(i2c_port) then
            log.error("sensor", "AirSHT30_1000 初始化失败")
        end
    end

    -- 主循环：等待定时器触发读取请求（每5秒一次）
    while true do
        sys.waitUntil("read_sensors_req")

        local current_temp, current_hum, current_voc

        -- 1. 读取温湿度
        current_temp, current_hum = air_sht30.read()
        if current_temp then
            log.info("sht30", string.format("温度:%.2f℃ 湿度:%.2f%%", current_temp, current_hum))
        else
            log.error("sht30", "读取温湿度失败")
        end

        -- 2. 读取 VOC (TVOC 浓度 ppb)
        current_voc = air_voc.get_ppb()
        if current_voc then
            log.info("voc", string.format("TVOC:%d ppb", current_voc))
        else
            log.error("voc", "读取VOC失败")
        end

        -- 发布 UI 数据（即使读取失败，对应值也为 nil）
        sys.publish("ui_sensor_data", current_temp, current_hum, current_voc)

        -- 只有当两个传感器本次均成功读取时，才发布云端数据并更新 last 值
        if current_temp and current_voc then
            last_temp, last_hum, last_voc = current_temp, current_hum, current_voc
            sys.publish("read_sht30_voc_rsp", current_temp, current_hum, current_voc)
            log.info("sensor", "两个传感器均成功，向云端发布更新数据请求")

            -- 如果是 Air1601，额外通过系统事件发送数据给 780EPM
            if rtos.bsp() == "Air1601" then
                local sensor_data = string.format("SENSOR_DATA:temp=%.2f,hum=%.2f,voc=%.0f",
                                                   current_temp, current_hum, current_voc)
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

-- 每 5 秒触发一次读取请求（可根据需要调整周期）
sys.timerLoopStart(function()
    sys.publish("read_sensors_req")
end, 5000)