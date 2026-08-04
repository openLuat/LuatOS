--[[
@module  rs485_app
@summary 双RS485收发管理
@version 2.0
@date    2026.08.04
@author  江访
@usage
UART1(115200,8N1,GPIO2=RE/DE) + UART11(115200,8N1,GPIO153=RE/DE)。
使用 uart.setup 内置 RS485 模式，由固件自动控制 RE/DE 方向切换。
- 数据到来时发布 RS485_DATA_RECEIVED(port, data)
- 订阅 RS485_SEND_REQUEST(port, data)
- 发送期间收到回环数据(半双工自回环)自动丢弃，不上报UI

日志约定：UI页面上的 Port1/Port2 对应物理串口 UART1/UART11。
]]

-- 串口配置
local RS485_1_PORT = 1
local RS485_2_PORT = 11

local RS485_1_BAUD = 115200
local RS485_2_BAUD = 115200

local RS485_1_RE_DE = 2   -- GPIO2 = RS485_1 RE/DE (高电平=发送, 低电平=接收)
local RS485_2_RE_DE = 153 -- GPIO153 = RS485_2 RE/DE (高电平=发送, 低电平=接收)

local RS485_DATA_BITS = 8
local RS485_STOP_BITS = 1
local RS485_PARITY = uart.NONE

-- 接收缓冲区配置
local RS485_RX_BUFF_SIZE = 1024

-- RS485 方向切换延时 (us), 参考官方 485 demo
local RS485_TX_DELAY = 20000

-- 正在发送的串口id(半双工回环抑制用): 发送期间置位, 发送完成清除
local sending_uart_id = nil

--[[
判断指定串口是否正处于发送状态(用于抑制自回环数据)

@local
@function is_sending
@param uart_id number 物理串口id
@return boolean 是否发送中
]]
local function is_sending(uart_id)
    return sending_uart_id == uart_id
end

-- UART1 接收回调 (使用循环读取, 与官方 demo 一致)
local function uart1_rx_cb(id, len)
    local data = ""
    repeat
        local s = uart.read(RS485_1_PORT, RS485_RX_BUFF_SIZE)
        if s and #s > 0 then
            data = data .. s
        end
    until s == nil or #s == 0

    if #data > 0 then
        -- 调试: 打印原始接收字节, 用于判断是硬件接收乱码还是UI显示问题
        log.info("rs485_app", "Port1(UART1) RX raw hex:", data:toHex())
        if is_sending(RS485_1_PORT) then
            -- 半双工自回环数据, 丢弃不上报
            log.info("rs485_app", "Port1(UART1) 回环数据丢弃:", #data, "bytes")
            return
        end
        log.info("rs485_app", "Port1(UART1) rx:", #data, "bytes")
        sys.publish("RS485_DATA_RECEIVED", 1, data)
    end
end

-- UART11 接收回调 (使用循环读取, 与官方 demo 一致)
local function uart11_rx_cb(id, len)
    local data = ""
    repeat
        local s = uart.read(RS485_2_PORT, RS485_RX_BUFF_SIZE)
        if s and #s > 0 then
            data = data .. s
        end
    until s == nil or #s == 0

    if #data > 0 then
        -- 调试: 打印原始接收字节, 用于判断是硬件接收乱码还是UI显示问题
        log.info("rs485_app", "Port2(UART11) RX raw hex:", data:toHex())
        if is_sending(RS485_2_PORT) then
            -- 半双工自回环数据, 丢弃不上报
            log.info("rs485_app", "Port2(UART11) 回环数据丢弃:", #data, "bytes")
            return
        end
        log.info("rs485_app", "Port2(UART11) rx:", #data, "bytes")
        sys.publish("RS485_DATA_RECEIVED", 2, data)
    end
end

--[[
发送任务(在task中执行，使用sys.wait)
RE/DE 方向切换由 uart.setup 内置 RS485 模式自动控制，
不再手动 gpio.set 操作 RE/DE 引脚。
使用 uart.on "sent" 事件精确等待发送完成。
]]
local function rs485_send_task()
    while true do
        -- sys.waitUntil 返回: result(是否等到), arg1(port), arg2(data), ...
        -- 不传超时=永久阻塞等待, 收到 RS485_SEND_REQUEST 消息才继续
        local ok, port, data = sys.waitUntil("RS485_SEND_REQUEST")
        if not ok then
            log.warn("rs485_app", "发送请求异常, 忽略")
            goto continue
        end

        local uart_id, port_name
        if port == 1 then
            uart_id = RS485_1_PORT
            port_name = "Port1(UART1)"
        elseif port == 2 then
            uart_id = RS485_2_PORT
            port_name = "Port2(UART11)"
        else
            log.warn("rs485_app", "无效端口号:", port, "忽略本次发送")
            -- 注意: 不能 return, 否则整个发送任务会退出, 永久停止处理后续发送
            -- 继续循环等待下一条发送请求
            goto continue
        end

        -- 数据长度(防御: data 可能是数字, 此时强制转字符串)
        local data_len = 0
        if type(data) == "string" then
            data_len = #data
        elseif type(data) == "number" then
            data = tostring(data)
            data_len = #data
        elseif data == nil then
            log.warn("rs485_app", "发送数据为空, 忽略")
            goto continue
        end

        log.info("rs485_app", port_name, "发送:", data_len, "bytes")

        -- 置位发送标志(抑制回环)
        sending_uart_id = uart_id

        -- 发送前清空RX缓冲, 丢弃历史残留(避免误把旧数据当新数据)
        uart.rxClear(uart_id)

        -- 发送数据 (固件自动控制RE/DE: 拉高→发送→等待移位完成→延时→拉低)
        local sent = uart.write(uart_id, data)
        log.info("rs485_app", port_name, "实际写入", sent, "bytes")

        -- 等待发送完成(使用sent事件, 最多等3秒防死锁)
        local sent_ok = sys.waitUntil("UART_SENT_" .. tostring(uart_id), 3000)
        if not sent_ok then
            log.warn("rs485_app", port_name, "发送完成事件超时, 按波特率估算等待")
            local wait_ms = math.ceil(data_len * 87 / 1000) + 2
            sys.wait(wait_ms)
        end

        -- uart.setup 的 delay 参数已处理总线保持和方向切换时间,
        -- 额外短暂延时确保固件已将 RE/DE 拉低、总线释放完毕
        sys.wait(2)

        -- 清空发送期间回环进RX缓冲的数据, 避免残留回环被误当接收数据显示到UI
        uart.rxClear(uart_id)

        -- 清除发送标志
        sending_uart_id = nil

        log.info("rs485_app", port_name, "发送完成")

        ::continue::
    end
end

--[[
UART1 发送完成回调: 发布事件供发送任务等待

@local
@function uart1_sent_cb
]]
local function uart1_sent_cb()
    sys.publish("UART_SENT_1")
end

--[[
UART11 发送完成回调: 发布事件供发送任务等待

@local
@function uart11_sent_cb
]]
local function uart11_sent_cb()
    sys.publish("UART_SENT_11")
end

-- 初始化
local function init_rs485()
    -- 初始化UART1 (内置RS485模式: pin485=GPIO2, rx_level=0低电平接收, delay=20000us)
    uart.setup(RS485_1_PORT, RS485_1_BAUD, RS485_DATA_BITS, RS485_STOP_BITS, RS485_PARITY, uart.LSB, RS485_RX_BUFF_SIZE, RS485_1_RE_DE, 0, RS485_TX_DELAY)
    uart.on(RS485_1_PORT, "receive", uart1_rx_cb)
    uart.on(RS485_1_PORT, "sent", uart1_sent_cb)

    -- 初始化UART11 (内置RS485模式: pin485=GPIO153, rx_level=0低电平接收, delay=20000us)
    uart.setup(RS485_2_PORT, RS485_2_BAUD, RS485_DATA_BITS, RS485_STOP_BITS, RS485_PARITY, uart.LSB, RS485_RX_BUFF_SIZE, RS485_2_RE_DE, 0, RS485_TX_DELAY)
    uart.on(RS485_2_PORT, "receive", uart11_rx_cb)
    uart.on(RS485_2_PORT, "sent", uart11_sent_cb)

    log.info("rs485_app", "init done (内置RS485模式: pin485=GPIO2/153, 115200, 8N1)")
end

init_rs485()
sys.taskInit(rs485_send_task)
