--[[
@module  rs485_app
@summary 双路隔离 RS485 收发管理（UART1 = 485_1，UART2 = 485_2）
@version 1.0
@date    2026.10.21
@author  江访

=== 硬件约定（Air8602）===

  UART1 = 485_1，收发方向脚 GPIO65
  UART2 = 485_2，收发方向脚 GPIO57（原理图标注 485_EN2）
  UART3 已给 Air6205 WiFi / Air780ER2 4G（airlink），本模块不碰。

  若 485_1 正常而 485_2 无波形，优先核对 485_2 的方向极性：
  在 config 的 hw.rs485.uart2 里加 level = 1 再试（默认 0）。

  方向脚由 uart.setup 第 8 参数（pin485）交给固件自动切 RE/DE，
  严禁在 config.power_on 或任何地方再 gpio.setup 这两个脚 —— 会把方向控制抢走。

=== 消息约定 ===

  订阅 RS485_SEND_REQ(port, data)        请求发送，port = 1/2
  发布 RS485_EVENT(port, "TX"|"RX", data) 收发事件，供 UI 展示 + 串口日志
  内部 RS485_SEND_WAKE                    仅用于唤醒发送任务

  为什么用「常驻订阅入队 + 队列唤醒」而不是在发送任务里直接
  sys.waitUntil("RS485_SEND_REQ")：发送任务在等 sent 事件时无法同时收请求，
  这段时间 UI 再 publish 的发送请求没有订阅者，会被直接丢弃（见 sys.publish 实现）。

=== 收发测试 ===

  UI 上 UART1 发送 "123"、UART2 发送 "456"，对端只做接收，不做任何自动应答。
  前提是 485_1 与 485_2 的 A-A、B-B 已用线对接。
]]

local cfg = ((_G.project_config or {}).hw or {}).rs485 or {}

-- 两路端口参数（config 没写时用 Air8602 的硬件事实兜底）
local function port_cfg(port)
    local c = (port == 1) and cfg.uart1 or cfg.uart2
    c = c or {}
    local fallback_pin = (port == 1) and 65 or 57
    return {
        port = port,
        name = "UART" .. tostring(c.id or port),
        id = c.id or port,
        baud = c.baud or 9600,
        dir_pin = c.dir_pin or fallback_pin,
        -- 方向脚空闲电平：默认 0（与 485_1 现网一致）。若某一路方向极性相反，
        -- 可在 config 里给该路加 level = 1。
        level = c.level or 0,
    }
end

local PORTS = { port_cfg(1), port_cfg(2) }

local RX_BUFF = cfg.rx_buff or 1024
-- RS485 方向切换延时(us)：9600 波特率官方建议 20000
local TX_DELAY = cfg.tx_delay or 20000

-- 按端口号取配置
local function get_port(port)
    for _, p in ipairs(PORTS) do
        if p.port == port then return p end
    end
    return nil
end

--[[
数据转可读文本：纯可打印 ASCII 原样输出，否则转十六进制

@local
@function fmt_data
@param data string 原始数据
@return string 可打印文本
]]
local function fmt_data(data)
    for i = 1, #data do
        local b = data:byte(i)
        if b < 32 or b > 126 then return data:toHex() end
    end
    return data
end

-- 发送中标记（按端口）：半双工自回环数据要丢弃，不能当接收上报
local sending = {}

-- 发送队列
local send_queue = {}

--[[
发送请求入口：只入队 + 唤醒任务，真正的串口操作全部在发送任务里做

@local
@function on_send_req
@param port number 端口号(1/2)
@param data string 待发送数据
]]
local function on_send_req(port, data)
    if type(data) == "number" then data = tostring(data) end
    if type(data) ~= "string" or #data == 0 then
        log.warn("rs485_app", "发送请求数据为空, 忽略, port =", port)
        return
    end
    send_queue[#send_queue + 1] = { port = port, data = data }
    sys.publish("RS485_SEND_WAKE")
end
sys.subscribe("RS485_SEND_REQ", on_send_req)

--[[
执行一次发送：等 sent 事件（最多 3s），超时按波特率估算

@local
@function do_send
@param port number 端口号(1/2)
@param data string 待发送数据
]]
local function do_send(port, data)
    local p = get_port(port)
    if not p then
        log.warn("rs485_app", "无效端口号:", port, "忽略本次发送")
        return
    end

    -- 置位发送标志：发送期间读到的数据是半双工回环，不上报 UI
    sending[port] = true
    uart.rxClear(p.id)

    local written = uart.write(p.id, data)
    if not written or written == 0 then
        -- 串口未就绪/写失败：不等 sent 事件，直接放弃本帧，避免卡满 3s
        log.warn("rs485_app", p.name .. " 写入失败，丢弃本帧")
        sending[port] = nil
        return
    end
    log.info("rs485_app", p.name .. " 发送：" .. fmt_data(data))

    local sent_ok = sys.waitUntil("RS485_SENT_" .. p.id, 3000)
    if not sent_ok then
        -- 部分平台/场景不发 sent 事件，按「10bit/字节」估算后继续
        local wait_ms = math.ceil(#data * 10 * 1000 / p.baud) + 20
        log.warn("rs485_app", p.name, "等待发送完成超时，按波特率估算", wait_ms, "ms")
        sys.wait(wait_ms)
    end

    -- uart.setup 的 delay 已处理总线保持，这里再让出 2ms 等 RE/DE 稳定回接收态
    sys.wait(2)
    -- 清掉发送期间回环进 RX 缓冲的字节
    uart.rxClear(p.id)
    sending[port] = nil

    sys.publish("RS485_EVENT", port, "TX", data)
end

--[[
发送任务：队列里有就逐条发，队列空就等唤醒

@local
@function send_task
]]
local function send_task()
    while true do
        sys.waitUntil("RS485_SEND_WAKE")
        while #send_queue > 0 do
            local item = table.remove(send_queue, 1)
            do_send(item.port, item.data)
        end
    end
end

--[[
接收回调构造：循环读到空为止（与官方 demo 一致，一次事件可能带多包）

@local
@function make_rx_cb
@param port number 端口号(1/2)
@return function uart receive 回调
]]
local function make_rx_cb(port)
    local p = get_port(port)
    return function()
        local data = ""
        repeat
            local s = uart.read(p.id, RX_BUFF)
            if s and #s > 0 then data = data .. s end
        until s == nil or #s == 0

        if #data == 0 then return end

        if sending[port] then
            log.info("rs485_app", p.name .. " 发送期间回环数据丢弃：" .. fmt_data(data))
            return
        end

        log.info("rs485_app", p.name .. " 接收：" .. fmt_data(data))
        sys.publish("RS485_EVENT", port, "RX", data)
    end
end

--[[
发送完成回调构造：发布 RS485_SENT_<uart_id> 供 do_send 等待

@local
@function make_sent_cb
@param uart_id number 物理串口 id
@return function uart sent 回调
]]
local function make_sent_cb(uart_id)
    return function()
        sys.publish("RS485_SENT_" .. uart_id)
    end
end

--[[
初始化两路串口：内置 RS485 模式（pin485 = 方向脚，rx_level = 0，delay = TX_DELAY）

@local
@function init_ports
]]
local function init_ports()
    for _, p in ipairs(PORTS) do
        uart.setup(p.id, p.baud, 8, 1, uart.NONE, uart.LSB, RX_BUFF, p.dir_pin, p.level, TX_DELAY)
        uart.on(p.id, "receive", make_rx_cb(p.port))
        uart.on(p.id, "sent", make_sent_cb(p.id))
        log.info("rs485_app", p.name, "初始化完成", p.baud, "8N1, 方向脚 GPIO" .. tostring(p.dir_pin))
    end
end

init_ports()
sys.taskInit(send_task)
