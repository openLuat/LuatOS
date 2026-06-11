--[[
@module  temp_hum_sensor
@summary 485温湿度传感器读取模块
@version 1.0
@date    2025.12.12
@author  马梦阳
@usage
本功能模块演示的内容为：
1、将设备配置为 modbus RTU 主站模式
2、读取485接口的温湿度传感器数据
3、每 2 秒读取一次传感器数据并解析温度和湿度值

注意事项：
1、该示例程序需要搭配 exmodbus 扩展库使用
2、参考对应传感器手册，配置从站地址、寄存器地址等参数

本文件没有对外接口，直接在 main.lua 中 require "temp_hum_sensor" 就可以加载运行；

本文件的对外接口有一个：
1、sys.publish("TEMP_HUMIDITY_UPDATE", temperature, humidity)，定位成功时通知订阅者模块；
    temperature: 温度值（浮点数℃，如 25.3）
    humidity: 湿度值（浮点数%RH，如 60.5）
]]

local exmodbus = require("exmodbus")
local led = require("led")

pins.setup(28,"GPIO37") 
pins.setup(18,"GPIO29") 
gpio.setup(29, 1) 

local rs485_dir_gpio = 37 -- RS485 方向引脚

-- 创建 RTU 主站配置参数
local create_config = {
    -- 串口配置参数；
    mode = exmodbus.RTU_MASTER,      -- 通信模式：RTU主站
    uart_id = 1,                     -- UART 端口号：1
    baud_rate = 9600,                -- 波特率：9600（根据传感器手册调整）
    data_bits = 8,                   -- 数据位：8
    stop_bits = 1,                   -- 停止位：1
    parity_bits = uart.None,         -- 校验位：无
    byte_order = uart.LSB,           -- 字节顺序：LSB（低位优先）
    rs485_dir_gpio = rs485_dir_gpio, -- RS485 方向引脚：37
    rs485_dir_rx_level = 0,          -- RS485 接收方向电平：0
    concat_timeout = 100,            -- 字符拼接超时时间：100 毫秒   
}


-- 初始化传感器数据结构
-- 用于记录传感器的温度和湿度值
local sensor_data = {
    temperature = 0, -- 温度值
    humidity = 0     -- 湿度值
}

-- 配置读取温湿度传感器的参数
local read_config = {
    slave_id = 1,                         -- 从站地址：1
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x001E,                  -- 起始地址：0x001E（温度寄存器）
    reg_count = 0x0002,                   -- 读取 2 个寄存器：温度和湿度
    timeout = 1000                        -- 超时时间 1000 ms
}


-- 创建 RTU 主站实例
local rtu_master = exmodbus.create(create_config)

-- 判断主站是否创建成功并记录日志
if not rtu_master then
    log.info("temp_hum_sensor", "RTU 主站创建失败")
else
    log.info("temp_hum_sensor", "RTU 主站创建成功")
end


-- 读取温湿度传感器数据的函数
local function read_temp_humidity()

    log.info("temp_hum_sensor", "开始读取温湿度传感器数据")

    -- 执行读取操作
    local read_result = rtu_master:read(read_config)

    -- 根据返回状态处理结果
    if read_result.status == exmodbus.STATUS_SUCCESS then
        -- 读取原始寄存器值
        local temp_raw = read_result.data[read_config.start_addr]
        local humi_raw = read_result.data[read_config.start_addr + 1]

        -- 处理温度值的符号位
        if temp_raw > 0x7FFF then
            temp_raw = temp_raw - 0x10000
        end

        -- 解析温度和湿度值
        sensor_data.temperature = temp_raw / 10.0
        sensor_data.humidity = humi_raw / 10.0

        log.info("temp_hum_sensor", "读取成功，温度为", sensor_data.temperature, "℃，湿度为", sensor_data.humidity, "%RH")

        led.sensor_ok()

        sys.publish("TEMP_HUMIDITY_UPDATE", sensor_data.temperature, sensor_data.humidity)
    elseif read_result.status == exmodbus.STATUS_DATA_INVALID then
        log.info("temp_hum_sensor", "收到传感器响应数据但数据损坏/校验失败")
    elseif read_result.status == exmodbus.STATUS_EXCEPTION then
        log.info("temp_hum_sensor", "收到传感器异常响应，标准异常码为", read_result.execption_code)
    elseif read_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("temp_hum_sensor", "未收到传感器的响应（超时）")
    end
end


-- 定时任务函数：每 2 秒读取一次温湿度数据
local function task()
    while true do
        if rtu_master then
            read_temp_humidity()
        else
            log.info("temp_hum_sensor", "RTU主站未创建，无法读取传感器数据")
        end
        sys.wait(5000)
    end
end

-- 初始化任务
sys.taskInit(task)
