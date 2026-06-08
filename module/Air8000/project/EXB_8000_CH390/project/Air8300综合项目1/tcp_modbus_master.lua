--[[
@module  tcp_modbus_master
@summary 建大仁科  TCP Modbus 温湿度读取模块
@version 1.0
@date    2026.05.19
@author  王城钧
@usage
本功能模块：将设备配置为 Modbus TCP 主站，读取建大仁科 RS-WS-ETH-6
温湿度变送器数据，每 5 秒读取一次，解析后发布 TEMP_HUMIDITY_UPDATE。

寄存器说明（保持寄存器，功能码 0x03）：
  0x0000  当前湿度  INT16  x10  （例：501 → 50.1%RH）
  0x0001  当前温度  INT16  x10  （例：253 → 25.3℃，负数已处理）

本文件没有对外接口，直接在 main.lua 中 require "tcp_modbus_master" 即可加载运行；

本文件的对外接口有一个：
1、sys.publish("TCP_TEMP_HUMIDITY_UPDATE", temperature, humidity)，定位成功时通知订阅者模块；
    temperature: 温度值（浮点数℃，如 25.3）
    humidity: 湿度值（浮点数%RH，如 60.5）
]]

local exmodbus = require("exmodbus")
local led = require("led")

-- 创建 TCP 主站配置参数
local create_config = {
    mode = exmodbus.TCP_MASTER,      -- 通信模式：TCP主站
    adapter = socket.LWIP_ETH,       -- 网卡 ID（根据实际网络适配器修改）
    ip_address = "192.168.1.100",    -- RS-WS-ETH-6 的 IP 地址
    port = 500,                     -- Modbus TCP 默认端口
}

-- 配置读取温湿度传感器的参数
local read_config = {
    slave_id = 1,                         -- 从站地址
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x0000,                  -- 起始地址：湿度 0x0000
    reg_count = 0x0002,                   -- 读取 2 个寄存器：湿度 + 温度
    timeout = 1000                        -- 超时时间 1000 ms
}

-- 传感器数据
local sensor_data = {
    temperature = 0,
    humidity = 0
}

-- 创建 TCP 主站实例
local tcp_master = exmodbus.create(create_config)

if not tcp_master then
    log.info("tcp_modbus_master", "TCP 主站创建失败")
else
    log.info("tcp_modbus_master", "TCP 主站创建成功")
end

-- 读取温湿度传感器数据的函数
local function read_temp_humidity()
    log.info("tcp_modbus_master", "开始读取温湿度传感器数据")

    local read_result = tcp_master:read(read_config)

    if read_result.status == exmodbus.STATUS_SUCCESS then
        local humi_raw = read_result.data[read_config.start_addr]      -- 0x0000 湿度
        local temp_raw = read_result.data[read_config.start_addr + 1]  -- 0x0001 温度

        if temp_raw > 0x7FFF then
            temp_raw = temp_raw - 0x10000
        end

        sensor_data.temperature = temp_raw / 10.0
        sensor_data.humidity = humi_raw / 10.0

        log.info("tcp_modbus_master", "读取成功，温度为", string.format("%.1f", sensor_data.temperature), "℃，湿度为", string.format("%.1f", sensor_data.humidity), "%RH")

        led.sensor_ok()

        sys.publish("TCP_TEMP_HUMIDITY_UPDATE", sensor_data.temperature, sensor_data.humidity)
    elseif read_result.status == exmodbus.STATUS_DATA_INVALID then
        log.info("tcp_modbus_master", "收到传感器响应数据但数据损坏/校验失败")
    elseif read_result.status == exmodbus.STATUS_EXCEPTION then
        log.info("tcp_modbus_master", "收到传感器异常响应，异常码为", read_result.execption_code)
    elseif read_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("tcp_modbus_master", "未收到传感器的响应（超时）")
    end
end

-- 定时任务：每 5 秒读取一次温湿度数据
local function task()
    sys.wait(6000) -- 等待网卡就绪
    while true do
        if tcp_master then
            read_temp_humidity()
        else
            log.info("tcp_modbus_master", "TCP主站未创建，无法读取传感器数据")
        end
        sys.wait(5000)
    end
end

sys.taskInit(task)
