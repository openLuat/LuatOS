--[[
@module  rs232_app
@summary 双RS232收发管理
@version 2.0
@date    2026.08.04
@author  江访
@usage
UART2(115200,8N1) + UART12(115200,8N1), 全双工, 无RE/DE控制。
- 数据到来时发布 RS232_DATA_RECEIVED(port, data)
- 订阅 RS232_SEND_REQUEST(port, data)

日志约定：UI页面上的 Port1/Port2 对应物理串口 UART2/UART12。
]]

-- 串口配置
local RS232_1_PORT = 2
local RS232_2_PORT = 12

local RS232_1_BAUD = 115200
local RS232_2_BAUD = 115200

local RS232_DATA_BITS = 8
local RS232_STOP_BITS = 1
local RS232_PARITY = uart.NONE

local RS232_RX_BUFF_SIZE = 1024

-- UART2 接收回调 (使用循环读取, 与官方 demo 一致)
local function uart2_rx_cb()
    local data = ""
    repeat
        local s = uart.read(RS232_1_PORT, RS232_RX_BUFF_SIZE)
        if s and #s > 0 then
            data = data .. s
        end
    until s == nil or #s == 0

    if #data > 0 then
        log.info("rs232_app", "Port1(UART2) RX raw hex:", data:toHex())
        log.info("rs232_app", "Port1(UART2) rx:", #data, "bytes")
        sys.publish("RS232_DATA_RECEIVED", 1, data)
    end
end

-- UART12 接收回调 (使用循环读取, 与官方 demo 一致)
local function uart12_rx_cb()
    local data = ""
    repeat
        local s = uart.read(RS232_2_PORT, RS232_RX_BUFF_SIZE)
        if s and #s > 0 then
            data = data .. s
        end
    until s == nil or #s == 0

    if #data > 0 then
        log.info("rs232_app", "Port2(UART12) RX raw hex:", data:toHex())
        log.info("rs232_app", "Port2(UART12) rx:", #data, "bytes")
        sys.publish("RS232_DATA_RECEIVED", 2, data)
    end
end

--[[
发送请求处理(在task中执行，全双工无需RE/DE)
使用 sys.waitUntil 正确解析多参数
]]
local function rs232_send_task()
    while true do
        -- sys.waitUntil 返回: result(是否等到), arg1(port), arg2(data), ...
        local ok, port, data = sys.waitUntil("RS232_SEND_REQUEST")
        if not ok then
            log.warn("rs232_app", "发送请求异常, 忽略")
            goto continue
        end

        local uart_id, port_name
        if port == 1 then
            uart_id = RS232_1_PORT
            port_name = "Port1(UART2)"
        elseif port == 2 then
            uart_id = RS232_2_PORT
            port_name = "Port2(UART12)"
        else
            log.warn("rs232_app", "无效端口号:", port, "忽略")
            goto continue
        end

        -- 防御: data 可能为 nil/number
        local data_len = 0
        if type(data) == "string" then
            data_len = #data
        elseif type(data) == "number" then
            data = tostring(data)
            data_len = #data
        elseif data == nil then
            log.warn("rs232_app", "发送数据为空, 忽略")
            goto continue
        end

        log.info("rs232_app", port_name, "发送:", data_len, "bytes")
        local sent = uart.write(uart_id, data)
        log.info("rs232_app", port_name, "实际写入", sent, "bytes")

        -- 全双工无需RE/DE, 发送后短暂延时即可
        sys.wait(1)

        ::continue::
    end
end

-- 初始化
local function init_rs232()
    uart.setup(RS232_1_PORT, RS232_1_BAUD, RS232_DATA_BITS, RS232_STOP_BITS, RS232_PARITY)
    uart.on(RS232_1_PORT, "receive", uart2_rx_cb)

    uart.setup(RS232_2_PORT, RS232_2_BAUD, RS232_DATA_BITS, RS232_STOP_BITS, RS232_PARITY)
    uart.on(RS232_2_PORT, "receive", uart12_rx_cb)

    log.info("rs232_app", "init done")
end

init_rs232()
sys.taskInit(rs232_send_task)
