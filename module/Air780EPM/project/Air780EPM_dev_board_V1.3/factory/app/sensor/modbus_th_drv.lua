--[[
@module  modbus_th_drv
@summary 485 温湿度传感器驱动（Modbus RTU 主站）
@version 1.0.0
@date    2026.10.16
@usage
通过 exmodbus 扩展库，以 Modbus RTU 主站模式读取 485 温湿度传感器（中盛科技气体浓度变送器 RS485 版）。

传感器参数（默认）：
  从站地址: 1
  波特率:   9600
  温度:     保持寄存器 0x001E，16 位有符号整数，-40~85℃，分辨率 0.1℃（值×0.1）
  湿度:     保持寄存器 0x001F，16 位无符号整数，0~85%RH，分辨率 0.1%RH（值×0.1）

对外接口：
  modbus_th_drv.read_temp_hum() → 返回温度(℃)、湿度(%RH)，失败返回 nil, nil

硬件（Air780EPM V1.3 开发板）：
  UART1（RS485），485 使能脚 GPIO24
]]

local exmodbus = require("exmodbus")

local modbus_th_drv = {}

-- RS485 方向控制引脚：V1.2 用 GPIO25，V1.3 用 GPIO24
local rs485_dir_gpio = 25
if HARDWARE_ENV == "DEV_BOARD_V1.3" then
    rs485_dir_gpio = 24
end

-- RS485 芯片供电 + vref 拉高
gpio.setup(1, 1)   -- RS485 芯片供电
gpio.setup(23, 1)  -- vref 拉高

-- RTU 主站创建参数
local create_config = {
    mode = exmodbus.RTU_MASTER,      -- RTU 主站
    uart_id = 1,                     -- UART1
    baud_rate = 9600,                -- 波特率 9600
    data_bits = 8,
    stop_bits = 1,
    parity_bits = uart.None,         -- 无校验
    byte_order = uart.LSB,           -- 低位优先
    rs485_dir_gpio = rs485_dir_gpio, -- 485 方向控制脚
    rs485_dir_rx_level = 0,          -- 接收方向电平：0=低（发送时拉高）
}

-- 读取参数：从站1，温度(0x001E) + 湿度(0x001F) 两个连续保持寄存器
local read_config = {
    slave_id = 1,
    reg_type = exmodbus.HOLDING_REGISTER,
    start_addr = 0x001E,
    reg_count = 0x0002,
    timeout = 1000
}

-- exmodbus debug 已关闭，正式固件不打印收发原始报文
exmodbus.debug(false)

local rtu_master = exmodbus.create(create_config)
if rtu_master then
    log.info("modbus_th_drv", "RTU 主站创建成功")
else
    log.error("modbus_th_drv", "RTU 主站创建失败")
end

--[[
读取温湿度
@return number|nil 温度(℃)
@return number|nil 湿度(%RH)
]]
function modbus_th_drv.read_temp_hum()
    if not rtu_master then
        return nil, nil
    end

    local read_result = rtu_master:read(read_config)

    if read_result.status == exmodbus.STATUS_SUCCESS then
        local temp_raw = read_result.data[read_config.start_addr]
        local humi_raw = read_result.data[read_config.start_addr + 1]

        -- 温度是 16 位有符号整数，处理符号位
        if temp_raw > 0x7FFF then
            temp_raw = temp_raw - 0x10000
        end

        local temp = temp_raw / 10.0
        local hum = humi_raw / 10.0

        -- 浮点除法可能产生 denormal 极小值（寄存器为 0 时会得到 0.000000e-308），归零处理
        if temp > -0.0001 and temp < 0.0001 then temp = 0 end
        if hum > -0.0001 and hum < 0.0001 then hum = 0 end

        return temp, hum
    elseif read_result.status == exmodbus.STATUS_DATA_INVALID then
        log.warn("modbus_th_drv", "响应数据损坏/校验失败")
    elseif read_result.status == exmodbus.STATUS_EXCEPTION then
        log.warn("modbus_th_drv", "传感器异常响应，异常码", read_result.execption_code)
    elseif read_result.status == exmodbus.STATUS_TIMEOUT then
        log.warn("modbus_th_drv", "未收到传感器响应（超时）")
    end

    return nil, nil
end

return modbus_th_drv
