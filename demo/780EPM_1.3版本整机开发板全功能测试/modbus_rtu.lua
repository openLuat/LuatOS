--[[
@module modbus_rtu
@summary modbus_rtu MODBUS_RTU协议 
@version 1.0
@date    2025.01.10
@author  HH
@usage
--注意:
--注意:
-- 用法实例
local modbus_rtu = require "modbus_rtu"

-- 初始化modbus_rtu
modbus_rtu.init({
    uartid = 1, -- 接收/发送数据的串口id
    baudrate = 4800, -- 波特率
    gpio_485 = 25, -- 转向GPIO编号
    tx_delay = 50000 -- 转向延迟时间，单位us

-- 定义modbus_rtu数据接收回调
local function on_modbus_rtu_receive(frame)
    log.info("modbus_rtu frame received:", json.encode(frame))
    if frame.fun == 0x03 then -- 功能码0x03表示读取保持寄存器
        local byte = frame.byte
        local payload = frame.payload
        -- log.info("modbus_rtu payload (hex):", payload:toHex())

        -- 解析数据(假设数据为16位寄存器值)
        local values_big = {} -- 大端序解析结果
        for i = 1, #payload, 2 do
            local msb = payload:byte(i)
            local lsb = payload:byte(i + 1)

            -- 大端序解析
            local result_big = (msb * 256) + lsb
            table.insert(values_big, result_big)
        end

        -- 输出大端序的解析结果
        log.info("输出大端序的解析结果:", table.concat(values_big, ", "))

        -- 第一个寄存器是湿度，第二个是温度，除以10以获取实际值
        if #values_big == 2 then
            log.info("测试同款485温湿度计")
            local humidity = values_big[1] / 10
            local temperature = values_big[2] / 10

            -- 打印湿度和温度
            log.info(string.format("湿度: %.1f%%", humidity))
            log.info(string.format("温度: %.1f°C", temperature))

        else
            log.info("用户自己的485下位机，共有" .. #values_big .. "组数据")
            for index, value in ipairs(values_big) do
                log.info(string.format("寄存器 %d: %d (大端序)", index, value))
            end

        end
    else
        log.info("功能码不是03")
    end
end

-- 设置modbus_rtu数据接收回调
modbus_rtu.set_receive_callback(1, on_modbus_rtu_receive)

local function send_modbus_rtu_command()
    local addr = 0x01 -- 设备地址,此处填客户自己的
    local fun = 0x03 -- 功能码（03为读取保持寄存器），此处填客户自己的
    local data = string.char(0x00, 0x00, 0x00, 0x02) -- 起始地址和寄存器数量(此处填客户自己的起始地址进而寄存器数量)

    -- modbus_rtu.send_command(1, addr, fun, data) -- 只发送一次命令并等待响应处理
    modbus_rtu.send_command(1, addr, fun, data, 5000) -- 循环5S发送一次

end

sys.taskInit(function()
    sys.wait(5000)
    send_modbus_rtu_command()

end)

]] local modbus_rtu = {}

-- 默认配置
local DEFAULT_CONFIG = {
    uartid = 1, -- 串口ID
    baudrate = 4800, -- 波特率
    databits = 8, -- 数据位
    stopbits = 1, -- 停止位
    parity = uart.None, -- 校验位
    endianness = uart.LSB, -- 字节序
    buffer_size = 1024, -- 缓冲区大小
    gpio_485 = 25, -- 485转向GPIO
    rx_level = 0, -- 485模式下RX的GPIO电平
    tx_delay = 10000 -- 485模式下TX向RX转换的延迟时间（us）
}

--[[
modbus_rtu初始化
@api modbus_rtu.init(config)
@number 
config为table，table里元素如下，用户根据自己实际情况修改对应参数，如果某个参数缺失会自动补充默认值，默认值为下
 config= {
    uartid = 1,          -- 串口ID
    baudrate = 4800,     -- 波特率
    databits = 8,        -- 数据位
    stopbits = 1,        -- 停止位
    parity = uart.None,  -- 校验位
    endianness = uart.LSB, -- 字节序
    buffer_size = 1024,  -- 缓冲区大小
    gpio_485 = 25,       -- 485转向GPIO
    rx_level = 0,        -- 485模式下RX的GPIO电平
    tx_delay = 10000,    -- 485模式下TX向RX转换的延迟时间（us）
}

@table 485转串口设置 
@return 无
@usage
modbus_rtu.init(config)
--]]

-- 初始化modbus_rtu
function modbus_rtu.init(config)
    config = config or {}
    -- 遍历 DEFAULT_CONFIG，为缺省的参数赋值
    for key, default_value in pairs(DEFAULT_CONFIG) do
        if config[key] == nil then
            config[key] = default_value
        end
    end
    -- 初始化UART
    uart.setup(config.uartid, config.baudrate, config.databits, config.stopbits, config.parity, config.endianness,
        config.buffer_size, config.gpio_485, config.rx_level, config.tx_delay)
    log.info("modbus_rtu 当前串口初始化配置为:", json.encode(config))
end

--[[
对数据进行CRC16_RTU校验
@api modbus_rtu.crc16()
@return int 原始数据对应的CRC16值

@usage
 local crc16_data = modbus_rtu.crc16("01024B")
log.info("crc16_data", crc16_data)
]]

function modbus_rtu.crc16(data)
    local crc16_data = crypto.crc16_modbus(data)
    -- log.info("crc16end = ",crc16_data)
    return crc16_data
end

--[[
对下位机返回过来的数据进行modbus_rtu解析
@api  modbus_rtu.parse_frame()
@number 下位机返回的数据（一般是hex的）
@return 成功返回table(地址码,功能码,有效字节数 ,真实数据值,crc校验值)失败返回nil和"CRC error"
@usage
 local crc16_data = modbus_rtu.parse_frame("01030401E6FF9F1BA0")
log.info("crc16_data", crc16_data.addr,crc16_data.fun,crc16_data.byte,crc16_data.payload,crc16_data.crc)
]]

function modbus_rtu.parse_frame(data)
    local str = data or 0X00
    local addr = str:byte(1) or 0X00 -- 地址位
    local fun = str:byte(2) or 0X00 -- 功能码
    local byte = str:byte(3) or 0X00 -- 有效字节数
    local payload = str:sub(4, 4 + byte - 1) or 0X00 -- 数据部分(根据有效字节数动态截取)
    local crc_data = str:sub(-2, -1) or 0X00
    local idx, crc = pack.unpack(crc_data, "H") -- CRC校验值

    -- 校验CRC
    if crc == modbus_rtu.crc16(str:sub(1, -3)) then
        log.info("modbus_rtu CRC校验成功")
        return {
            addr = addr,
            fun = fun,
            byte = byte,
            payload = payload,
            crc = crc
        }
    else
        log.info("modbus_rtu CRC校验失败", crc)
        return nil, "CRC error"
    end
end

-- 确保build_frame使用正确的CRC和帧结构
function modbus_rtu.build_frame(addr, fun, data)
    local frame = string.char(addr, fun) .. data
    local crc = modbus_rtu.crc16(frame)
    -- log.info("CRC部分为",crc:toHex())
    local pack_crc = pack.pack("H", crc)
    -- log.info("pack后CRC为",aaa:toHex())
    return frame .. pack_crc
end

--[[
对发送给下位机的数据进行校验和发送次数的设置
@api  modbus_rtu.send_command(uartid, addr, fun, data, interval)
@number uartid 485转串口对应的串口id，main_uart为1，aux_uart为2
@number addr 发送给下位机命令里的地址码
@number fun 发送给下位机命令里的功能码
@number data 发送给下位机命令里的有效字节数和命令码
@number interval(可选) 为nil时命令只发一次，为数字时时间隔发送命令的秒数
@return 成功返回table(地址码,功能码,有效字节数 ,真实数据值,crc校验值)失败返回nil和"CRC error"
@usage
 local crc16_data = modbus_rtu.parse_frame("01030401E6FF9F1BA0")
log.info("crc16_data", crc16_data.addr,crc16_data.fun,crc16_data.byte,crc16_data.payload,crc16_data.crc)
]]

-- 发送modbus_rtu命令
function modbus_rtu.send_command(uartid, addr, fun, data, interval)
    local cmd = modbus_rtu.build_frame(addr, fun, data)
    if interval then
        -- 如果传入了interval，则启用循环发送
        sys.timerLoopStart(function()
            log.info("每隔" .. interval .. "秒发一次指令", cmd:toHex())
            uart.write(uartid, cmd)
        end, interval)
        -- sys.timerLoopStart(uart.write, interval, uartid, cmd)
        -- log.info("modbus_rtu 循环发送的间隔时间为", interval, "ms",cmd:toHex())
    else
        -- 否则只发送一次
        uart.write(uartid, cmd)
        -- log.info("modbus_rtu 只发送一次", cmd:toHex())
    end
end

-- 设置modbus_rtu数据接收回调
function modbus_rtu.set_receive_callback(uartid, callback)
    uart.on(uartid, "receive", function(id, len)
        local s = ""
        repeat
            s = uart.read(id, 128)
            if #s > 0 then
                log.info("modbus_rtu 收到的下位机回复:", s:toHex())
                local frame, err = modbus_rtu.parse_frame(s)
                if frame then
                    callback(frame)
                else
                    log.info("modbus_rtu 数据错误", err)
                end
            end
        until s == ""
    end)
end

-- 设置modbus_rtu数据发送回调
function modbus_rtu.set_sent_callback(uartid, callback)
    uart.on(uartid, "sent", function(id)
        log.info("modbus_rtu 数据发送:", id)
        if callback then
            callback(id)
        end
    end)
end

return modbus_rtu
