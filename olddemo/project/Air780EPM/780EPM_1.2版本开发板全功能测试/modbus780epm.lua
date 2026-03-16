
-- 如果你用的是合宙DTU整机系列，才需要打开，否则按自己设计的PCB来
gpio.setup(1, 1) -- 485转TTL芯片供电打开
-- gpio.setup(24, 1) -- 外置供电电源打开

modbus_rtu = require("modbus_rtu")
local uartid = 1
-- 初始化modbus_rtu
modbus_rtu.init({
    uartid = uartid, -- 接收/发送数据的串口id
    baudrate = 4800, -- 波特率
    gpio_485 = 25, -- 转向GPIO编号(1.2版本开发板是GPIO25)
    tx_delay = 50000 -- 转向延迟时间，单位us(4800的最佳转向时间为50000,9600为20000,可以咨询下位机厂家推荐的转向延迟时间)
    -- 下面这些数据不填也行，不填底层默认为如下参数
    -- databits = 8,--数据位
    -- stopbits = 1,--停止位
    -- parity = uart.None,--校验位
    -- endianness = uart.LSB,--大小端
    -- buffer_size = 1024,--缓冲区大小
    -- rx_level = 0,--rx初始电平
})

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

            -- 发布湿度和温度
            sys.publish("modbus_rtu_data", {humidity, temperature})
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
modbus_rtu.set_receive_callback(uartid, on_modbus_rtu_receive)

local function send_modbus_rtu_command()
    local addr = 0x01 -- 设备地址,此处填客户自己的
    local fun = 0x03 -- 功能码（03为读取保持寄存器），此处填客户自己的
    local data = string.char(0x00, 0x00, 0x00, 0x02) -- 起始地址和寄存器数量(此处填客户自己的起始地址进而寄存器数量)

    -- modbus_rtu.send_command(1, addr, fun, data) -- 只发送一次命令并等待响应处理
    modbus_rtu.send_command(uartid, addr, fun, data, 5000) -- 循环5S发送一次

end

sys.taskInit(function()
    sys.wait(5000)
    send_modbus_rtu_command()
end)