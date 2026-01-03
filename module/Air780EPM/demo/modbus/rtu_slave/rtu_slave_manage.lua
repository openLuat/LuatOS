--[[
@module  rtu_slave_manage
@summary RTU 从站应用模块
@version 1.0
@date    2025.12.29
@author  马梦阳
@usage
本功能模块演示的内容为：
1、将设备配置为 modbus RTU 从站模式
2、等待并且应答主站请求

注意事项：
1、该示例程序需要搭配 exmodbus 扩展库使用
2、设备作为 modbus RTU 从站模式时，仅支持接收 modbus RTU 标准格式的请求报文
3、进行回应时也需要符合 modbus RTU 标准格式

本文件没有对外接口,直接在 main.lua 中 require "rtu_slave_manage" 就可以加载运行；
]]

local exmodbus = require("exmodbus")

gpio.setup(1, 1)          -- Air780EPM RS485 芯片供电引脚
gpio.setup(23, 1)         -- Air780EPM vref 脚拉高
local rs485_dir_gpio = 24 -- Air780EPM RS485 方向引脚（V1.2 开发板是 25，V1.3 开发板是 24）


-- 创建 RTU 从站配置参数
-- 说明：创建 RTU 从站时只需要配置如下参数即可
local rtu_slave_config = {
    -- 串口配置参数
    mode = exmodbus.RTU_SLAVE,       -- 通信模式
    uart_id = 1,                     -- UART 端口号
    baud_rate = 115200,              -- 波特率
    data_bits = 8,                   -- 数据位
    stop_bits = 1,                   -- 停止位
    parity_bits = uart.None,         -- 校验位
    byte_order = uart.LSB,           -- 字节顺序
    rs485_dir_gpio = rs485_dir_gpio, -- RS485 方向引脚
    rs485_dir_rx_level = 0,          -- RS485 接收方向电平
}


-- 当前从站地址（ID 号）
local SLAVE_ID = 1


-- 寄存器映射表（按类型组织）
local modbus_data = {
    coils = {},            -- 线圈，可读可写，布尔值 (0/1)
    inputs = {},           -- 输入状态，只读，布尔值 (0/1)
    input_registers = {},  -- 输入寄存器，只读，16 位无符号整数
    holding_registers = {} -- 保持寄存器，可读可写，16 位无符号整数
}


-- 初始化一些默认值，便于测试
for i = 0, 3 do
    modbus_data.coils[i] = 0
    modbus_data.inputs[i] = 1
    modbus_data.input_registers[i] = 100 + i
    modbus_data.holding_registers[i] = 200 + i
end


-- 创建 RTU 从站实例
local rtu_slave = exmodbus.create(rtu_slave_config)

-- 判断从站是否创建成功
if not rtu_slave then
    log.info("exmodbus_test", "rtu_slave 创建失败")
else
    log.info("exmodbus_test", "rtu_slave 创建成功, 从站 ID 为", SLAVE_ID)
end


-- 定义主站请求处理回调函数
local function callback(request)
    log.info("exmodbus_test", "rtu_slave 收到主站请求")

    -- 检查从站 ID 是否匹配
    if request.slave_id ~= SLAVE_ID then
        log.info("exmodbus_test", "从站 ID 不匹配，请求从站 ID 为", request.slave_id, "，当前从站 ID 为", SLAVE_ID)
        return nil
    end

    -- 根据功能码和寄存器类型，匹配对应的数据表
    local data_table = nil
    local is_write = false -- 标记是否为写操作

    -- 检查请求的功能码是否支持
    if request.func_code == exmodbus.READ_COILS then -- 读线圈
        data_table = modbus_data.coils
    elseif request.func_code == exmodbus.READ_DISCRETE_INPUTS then -- 读离散输入
        data_table = modbus_data.inputs
    elseif request.func_code == exmodbus.READ_HOLDING_REGISTERS then -- 读保持寄存器
        data_table = modbus_data.holding_registers
    elseif request.func_code == exmodbus.READ_INPUT_REGISTERS then -- 读输入寄存器
        data_table = modbus_data.input_registers
    elseif request.func_code == exmodbus.WRITE_SINGLE_COIL or request.func_code == exmodbus.WRITE_MULTIPLE_COILS then -- 写单个/多个线圈
        is_write = true
        data_table = modbus_data.coils
    elseif request.func_code == exmodbus.WRITE_SINGLE_HOLDING_REGISTER or request.func_code == exmodbus.WRITE_MULTIPLE_HOLDING_REGISTERS then -- 写单个/多个保持寄存器
        is_write = true
        data_table = modbus_data.holding_registers
    else
        -- 不支持的功能码
        log.info("exmodbus_test", "不支持的功能码: ", request.func_code)
        return exmodbus.ILLEGAL_FUNCTION
    end

    -- 检查数据地址是否有效
    local end_addr = request.start_addr + request.reg_count - 1

    -- 假设每种寄存器的最大地址是 3 (即 0 - 3)
    if request.start_addr < 0 or end_addr > 3 then
        log.info("exmodbus_test", "数据地址超出范围，起始地址为", request.start_addr, "结束地址为", end_addr)
        return exmodbus.ILLEGAL_DATA_ADDRESS
    end

    -- 处理读取操作
    if not is_write then
        -- 构造响应数据表
        local response = {}
        for i = 0, request.reg_count - 1 do
            local addr = request.start_addr + i
            response[addr] = data_table[addr]
        end
        log.info("exmodbus_test", "读取成功，返回数据: ", table.concat(response, ", "))
        return response
    end

    -- 处理写入操作
    if is_write then
        -- 执行写入操作
        for i = 0, request.reg_count - 1 do
            local addr = request.start_addr + i
            data_table[addr] = request.data[addr]
            log.info("exmodbus_test", "写入成功，写入地址: ", addr, "写入数据: ", request.data[addr])
        end
        return {} -- 返回空表表示成功
    end
end


-- 注册主站请求处理回调函数
rtu_slave:on(callback)

log.info("从站回调函数已注册，开始监听主站请求...")
