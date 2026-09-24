--[[
@module  temp_sensor
@summary 485温湿度传感器读取模块（非隔离口 UART3）
@version 1.1
@date    2026.09.18
@usage
本功能模块演示的内容为：
1、将设备配置为 modbus RTU 主站模式（非隔离485，UART3）
2、读取485接口的温湿度传感器数据（从站地址1）
3、每 5 秒读取一次传感器数据并解析温度和湿度值

注意事项：
1、该示例程序需要搭配 exmodbus 扩展库使用
2、参考对应传感器手册，配置从站地址、寄存器地址等参数

对外接口：
1、sys.publish("TEMP_HUMIDITY_UPDATE", temperature, humidity)，采集成功时通知订阅者模块；
    temperature: 温度值（浮点数℃，如 25.3）
    humidity: 湿度值（浮点数%RH，如 60.5）
]]

local exmodbus = require "exmodbus"
local comm_core = require "comm_core"

-- 非隔离485对应 UART3，管脚映射（参考 Air8300 工控板）
pins.setup(25, "UART3_RX")      -- 非隔离485 接收脚复用（UART3）
pins.setup(26, "UART3_TX")      -- 非隔离485 发送脚复用（UART3）
pins.setup(27, "GPIO36")        -- 非隔离485 方向脚复用（UART3）
-- 说明：RS485 芯片电源脚（GPIO29）的引脚复用与拉高已统一由 net_drv 初始化，避免多处重复 setup

-- RS485 方向引脚（非隔离口）
local rs485_dir_gpio = 36

-- 创建 RTU 主站配置参数（UART3 / 非隔离485）
local create_config = {
    mode = exmodbus.RTU_MASTER,      -- 通信模式：RTU主站
    uart_id = 3,                     -- UART 端口号：3（非隔离485）
    baud_rate = 9600,                -- 波特率：9600
    data_bits = 8,                   -- 数据位：8
    stop_bits = 1,                   -- 停止位：1
    parity_bits = uart.None,         -- 校验位：无
    byte_order = uart.LSB,           -- 字节顺序：LSB（低位优先）
    rs485_dir_gpio = rs485_dir_gpio, -- RS485 方向引脚：36
    rs485_dir_rx_level = 0,          -- RS485 接收方向电平：0
    concat_timeout = 100,            -- 字符拼接超时时间：100 毫秒
}

-- 传感器数据结构（记录温度/湿度）
local sensor_data = {
    temperature = 0,  -- 温度值
    humidity = 0      -- 湿度值
}

-- 读取温湿度传感器的参数（从站地址1）
local read_config = {
    slave_id = 1,                         -- 从站地址：1
    reg_type = exmodbus.HOLDING_REGISTER, -- 寄存器类型：保持寄存器
    start_addr = 0x001E,                  -- 起始地址：0x001E（温度寄存器）
    reg_count = 0x0002,                   -- 读取 2 个寄存器：温度和湿度
    timeout = 1000                        -- 超时时间 1000 ms
}

-- 创建 RTU 主站实例
local rtu_master = comm_core.create_master(create_config)
if not rtu_master then
    log.error("temp_sensor", "RTU 主站创建失败（UART3）")
end

-- 读取温湿度传感器数据的函数
local function read_temp_humidity()
    if not rtu_master then return end

    log.info("temp_sensor", "开始读取温湿度传感器数据")

    -- 执行读取操作
    local status, read_result = comm_core.read_regs(rtu_master, read_config)

    -- 根据返回状态处理结果
    if status == exmodbus.STATUS_SUCCESS and read_result then
        -- 读取原始寄存器值
        local temp_raw = read_result.data[read_config.start_addr]
        local humi_raw = read_result.data[read_config.start_addr + 1]

        -- 寄存器缺失（如应答帧解析异常）时不更新数据，避免用 0 覆盖上一轮的有效值
        if type(temp_raw) ~= "number" or type(humi_raw) ~= "number" then
            log.warn("temp_sensor", "寄存器数据缺失, 本轮不更新")
            return
        end

        -- 处理温度值的符号位
        if temp_raw > 0x7FFF then
            temp_raw = temp_raw - 0x10000
        end

        -- 解析温度和湿度值
        local temperature = temp_raw / 10.0
        local humidity = humi_raw / 10.0

        -- 合理区间校验：越界说明帧内容不可信（总线受扰/帧错乱），丢弃本轮并告警，
        -- 避免把 6553.5 之类的离谱值上报到平台触发误告警
        if temperature < -40 or temperature > 125 or humidity < 0 or humidity > 100 then
            log.warn("temp_sensor", "温湿度值越界, 丢弃本轮: 温度=", temperature, "湿度=", humidity)
            return
        end

        sensor_data.temperature = temperature
        sensor_data.humidity = humidity

        log.info("temp_sensor", "温度:", sensor_data.temperature, "度 湿度:", sensor_data.humidity, "%RH")

        -- 发布温湿度更新消息，通知其他模块
        sys.publish("TEMP_HUMIDITY_UPDATE", sensor_data.temperature, sensor_data.humidity)
    elseif status == exmodbus.STATUS_TIMEOUT then
        log.warn("temp_sensor", "温湿度传感器读取超时")
    else
        log.warn("temp_sensor", "温湿度传感器读取失败, 状态=", status)
    end
end

-- 温湿度采集任务（每 5 秒一次）
local function temp_hum_sensor_task()
    while true do
        if rtu_master then
            read_temp_humidity()
        end
        sys.wait(5000) -- 5 秒读取一次
    end
end

-- 创建并启动采集任务
sys.taskInit(temp_hum_sensor_task)
