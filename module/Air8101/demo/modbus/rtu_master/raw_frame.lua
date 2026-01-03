--[[
@module  raw_frame
@summary RTU 主站应用模块（原始帧方式）
@version 1.0
@date    2025.12.31
@author  马梦阳
@usage
本功能模块演示的内容为：
1、将设备配置为 modbus RTU 主站模式
2、与从站 1 和 从站 2 进行通信
    1. 对从站 1 进行 2 秒一次的读取保持寄存器 0-1 操作
    2. 对从站 2 进行 4 秒一次的写入保持寄存器 0-1 操作

注意事项：
1、该示例程序需要搭配 exmodbus 扩展库使用
2、本功能模块只适合使用非标准 modbus RTU 请求报文格式的用户
3、如果你使用的是标准 modbus RTU 请求报文格式，请参考 param_field 功能模块

本文件没有对外接口,直接在 main.lua 中 require "raw_frame" 就可以加载运行；
]]

local exmodbus = require("exmodbus")


-- 创建 RTU 主站配置参数；
-- 说明：创建 RTU 主站时只需要配置如下参数即可；
-- 演示时使用的是 Air8101 核心板，Air8101 核心板不带 485 接口，所以需要外接 485 转串口模块
-- 演示时使用的 485 转串口模块，模块硬件自动切换方向，不需要软件 io 控制
-- 如果外接的 485 转串口模块的方向引脚连接到了 Air8101 核心板的 GPIO 引脚
-- 则需要配置 rs485_dir_gpio 为对应的 GPIO 引脚号
-- 同时也需要配置 rs485_dir_rx_level 为 0 或 1，默认为 0
local create_config = {
    -- 串口配置参数；
    mode = exmodbus.RTU_MASTER,      -- 通信模式
    uart_id = 1,                     -- UART 端口号
    baud_rate = 115200,              -- 波特率
    data_bits = 8,                   -- 数据位
    stop_bits = 1,                   -- 停止位
    parity_bits = uart.None,         -- 校验位
    byte_order = uart.LSB,           -- 字节顺序
    -- rs485_dir_gpio = rs485_dir_gpio, -- RS485 方向引脚
    -- rs485_dir_rx_level = 0,          -- RS485 接收方向电平
}

-- 初始化从站 1 数据结构
-- 用于记录从站 1 保持寄存器 0-1 的值；
local slave1_data = {}

-- 配置读取从站 1 保持寄存器 0-1 的值；
local read_config = {
    raw_request = string.char(
        0x01,           -- 从站地址
        0x03,           -- 功能码：读取保持寄存器
        0x00, 0x00,     -- 寄存器起始地址
        0x00, 0x02,     -- 寄存器数量
        0xC4, 0x0B      -- CRC16校验码
    ),
    timeout = 1000      -- 超时时间 1000 ms
}


-- 配置写入从站 2 保持寄存器 0-1 的值；
local write_config = {
    raw_request = string.char(
        0x02,           -- 从站地址
        0x10,           -- 功能码：写入保持寄存器
        0x00, 0x00,     -- 寄存器起始地址
        0x00, 0x02,     -- 寄存器数量
        0x04,           -- 字节数量
        0x00, 0x12,     -- 寄存器 0 的值
        0x00, 0x34,     -- 寄存器 1 的值
        0x5D, 0x39      -- CRC16校验码
    ),
    timeout = 1000,     -- 超时时间 1000 ms
}


-- 创建 RTU 主站实例
local rtu_master = exmodbus.create(create_config)


-- 判断主站是否创建成功并记录日志
if not rtu_master then
    log.info("exmodbus_test", "rtu_master 创建失败")
else
    log.info("exmodbus_test", "rtu_master 创建成功")
end


-- 读取从站 1 保持寄存器数据的函数
local function read_slave1_holding_registers()

    log.info("exmodbus_test", "开始读取从站 1 保持寄存器 0-1 的值")

    -- 执行读取操作
    local read_result = rtu_master:read(read_config)

    -- 根据返回状态处理结果
    if read_result.status == exmodbus.STATUS_SUCCESS then
        local resp = read_result.raw_response

        -- 特别说明：
        -- 接下来的判断是针对 modbus RTU 标准响应格式的应答原始帧来解析的
        -- 在实际项目中，应根据自己项目中的实际应答原始帧格式进行解析
        -- 如果实际格式与此处演示的格式不一致，需要修改接下来的解析代码

        -- 1. 检查总长度：必须为 9 字节（1 地址 + 1 功能码 + 1 字节数 + 4 数据 + 2 CRC）
        if #resp ~= 9 then
            log.info("exmodbus_test", "响应长度错误，期望 9 字节，实际:", #resp)
            return
        end

        -- 2. 检查从站地址
        if string.byte(resp, 1) ~= 0x01 then
            log.info("exmodbus_test", "从站地址不匹配，收到:", string.byte(resp, 1))
            return
        end

        -- 3. 检查功能码
        local func_code = string.byte(resp, 2)
        if func_code == 0x83 then
            local exc_code = string.byte(resp, 3)
            log.info("exmodbus_test", "从站返回异常响应，异常码:", exc_code)
            return
        elseif func_code ~= 0x03 then
            log.info("exmodbus_test", "功能码错误，收到:", func_code)
            return
        end

        -- 4. 检查字节数字段（应为 4）
        local byte_count = string.byte(resp, 3)
        if byte_count ~= 4 then
            log.info("exmodbus_test", "字节数字段错误，期望 4，实际:", byte_count)
            return
        end

        -- 5. 校验CRC
        -- 计算前 7 字节的 CRC
        local crc_calculated = crypto.crc16_modbus(resp:sub(1, 7))
        -- 提取接收到的 CRC
        local crc_received = string.unpack("<I2", resp, 8)
        -- 比较 CRC
        if crc_calculated ~= crc_received then
            log.info("exmodbus_test", "CRC 校验错误，计算值:", crc_calculated, "，接收值:", crc_received)
            return
        end

        -- 6. 解析寄存器数据（从第 4 字节开始，大端序）
        local data1 = string.unpack(">I2", resp, 4) -- 寄存器 0，偏移 4
        local data2 = string.unpack(">I2", resp, 6) -- 寄存器 1，偏移 6

        -- 7. 记录数据
        slave1_data[0] = data1
        slave1_data[1] = data2

        -- 8. 记录日志
        log.info("exmodbus_test", "成功读取到从站 1 保持寄存器 0-1 的值，寄存器 0 数值为", slave1_data[0], "，寄存器 1 数值为", slave1_data[1])
    elseif read_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("exmodbus_test", "未收到从站 1 的响应（超时）")
    end
end


-- 写入从站 2 保持寄存器数据的函数
local function write_slave2_holding_registers()

    log.info("exmodbus_test", "开始写入从站 2 保持寄存器 0-1 的值")

    -- 执行写入操作
    local write_result = rtu_master:write(write_config)

    -- 根据返回状态处理结果
    if write_result.status == exmodbus.STATUS_SUCCESS then
        local resp = write_result.raw_response

        -- 特别说明：
        -- 接下来的判断是针对 modbus RTU 标准响应格式的应答原始帧来解析的
        -- 在实际项目中，应根据自己项目中的实际应答原始帧格式进行解析
        -- 如果实际格式与此处演示的格式不一致，需要修改接下来的解析代码

        -- 1. 检查总长度：必须为 8 字节（1 地址 + 1 功能码 + 2 起始地址 + 2 寄存器数量 + 2 CRC）
        if #resp ~= 8 then
            log.info("exmodbus_test", "响应长度错误，期望 8 字节，实际:", #resp)
            return
        end

        -- 2. 检查从站地址
        if string.byte(resp, 1) ~= 0x02 then
            log.info("exmodbus_test", "从站地址不匹配，收到:", string.byte(resp, 1))
            return
        end

        -- 3. 检查功能码
        local func_code = string.byte(resp, 2)
        if func_code == 0x90 then
            local exc_code = string.byte(resp, 3)
            log.info("exmodbus_test", "从站返回异常响应，异常码:", exc_code)
            return
        elseif func_code ~= 0x10 then
            log.info("exmodbus_test", "功能码错误，收到:", func_code)
            return
        end

        -- 4. 检查起始地址（应为 0x0000）
        local start_addr = string.unpack(">I2", resp, 3)
        if start_addr ~= 0x0000 then
            log.info("exmodbus_test", "起始地址不匹配，收到:", start_addr)
            return
        end

        -- 5. 检查寄存器数量（应为 0x0002）
        local reg_count = string.unpack(">I2", resp, 5)
        if reg_count ~= 0x0002 then
            log.info("exmodbus_test", "寄存器数量错误，期望 0x0002，实际:", reg_count)
            return
        end

        -- 6. 校验CRC
        -- 计算前 6 字节的 CRC
        local crc_calculated = crypto.crc16_modbus(resp:sub(1, 6))
        -- 提取接收到的 CRC
        local crc_received = string.unpack("<I2", resp, 7)
        -- 比较 CRC
        if crc_calculated ~= crc_received then
            log.info("exmodbus_test", "CRC 校验错误，计算值:", crc_calculated, "，接收值:", crc_received)
            return
        end

        log.info("exmodbus_test", "成功写入从站 2 保持寄存器 0-1")
    elseif write_result.status == exmodbus.STATUS_TIMEOUT then
        log.info("exmodbus_test", "未收到从站 2 的响应（超时）")
    end
end

-- 定时任务函数：每 2 秒调用一次读取函数，每 4 秒调用一次写入函数
local function task()

    local count = 0 -- 计数器

    while true do
        if rtu_master then
            -- 每 2 秒调用一次读取函数
            read_slave1_holding_registers()
            if count == 0 then
                -- 每 4 秒调用一次写入函数
                write_slave2_holding_registers()
            end
            count = (count + 1) % 2
        else
            log.info("exmodbus_test", "rtu_master 未创建，无法执行 read_slave1_holding_registers()")
        end
        sys.wait(2000)
    end
end


-- 初始化任务
sys.taskInit(task)
