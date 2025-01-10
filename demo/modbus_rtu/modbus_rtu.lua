local modbus_rtu = {}

-- 默认配置
local DEFAULT_CONFIG = {
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
    uart.setup(
        config.uartid, config.baudrate, config.databits, config.stopbits,
        config.parity, config.endianness, config.buffer_size,
        config.gpio_485, config.rx_level, config.tx_delay
    )
    log.info("modbus_rtu 当前串口初始化配置为:", json.encode(config))
end

-- modbus_rtu CRC16校验
function modbus_rtu.crc16(data)
    return crypto.crc16("modbus_rtu", data)
end

-- 解析modbus_rtu数据帧
function modbus_rtu.parse_frame(data)
    local str = data or ""
    local addr = str:byte(1) or"" -- 地址位
    local fun = str:byte(2) or ""  -- 功能码
    local byte = str:byte(3)or "" -- 有效字节数
    local payload = str:sub(4, 4 + byte - 1)or"" -- 数据部分(根据有效字节数动态截取)
    local idx, crc = pack.unpack(str:sub(-2, -1), "H")or "" -- CRC校验值

    -- 校验CRC
    if crc == modbus_rtu.crc16(str:sub(1, -3)) then
        log.info("modbus_rtu CRC校验成功")
        return {
            addr = addr,
            fun = fun,
            byte = byte,
            payload = payload,
            crc = crc,
        }
    else
        log.info("modbus_rtu CRC校验失败")
        return nil, "CRC error"
    end
end

-- 确保build_frame使用正确的CRC和帧结构
function modbus_rtu.build_frame(addr, fun, data)
    local frame = string.char(addr, fun) .. data
    local crc = modbus_rtu.crc16(frame)
    return frame .. pack.pack("H", crc)
end

-- 发送modbus_rtu命令
function modbus_rtu.send_command(uartid, addr, fun, data, interval)
    local cmd = modbus_rtu.build_frame(addr, fun, data)
    if interval then
        -- 如果传入了interval，则启用循环发送
        sys.timerLoopStart(function ()
            log.info("每隔"..interval.."秒发一次指令",cmd:toHex())
            uart.write(uartid,cmd)
        end,interval)
        -- sys.timerLoopStart(uart.write, interval, uartid, cmd)
        log.info("modbus_rtu 循环发送的间隔时间为", interval, "ms",cmd:toHex())
    else
        -- 否则只发送一次
        uart.write(uartid, cmd)
        log.info("modbus_rtu 只发送一次", cmd:toHex())
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
        if callback then callback(id) end
    end)
end

return modbus_rtu