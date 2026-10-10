--[[
@module  modbus_master
@summary Modbus RTU 主站（RS485 / UART2），手动方向控制版
@version 2.0.0
@date    2026.09.15
@author  嵌入式软件设计开发代理
@usage
背景：Air8782P2 板载 485（UART2，收发器供电 GPIO26，方向 GPIO31）。
     现场实测使用 exmodbus（内部 uart.setup 自动换向）时出现"能发不能收"——
     硬件自动换向未把方向脚切回接收态，发送器占用总线，导致收不到从站应答
     （合宙官方 FAQ #73 描述的一致现象）。

方案：默认不依赖硬件自动换向，改为"手动控制方向脚"（config_app.rs485_dir_mode="manual"）：
     1. 发送前 GPIO31 拉高（发送态）；
     2. uart.write 发送请求；
     3. "sent" 发送完成回调中【立即】把 GPIO31 拉低（接收态）——尽量缩短发送态占用总线时间；
     4. 收应答帧（首字节后连续静默判帧）；
     5. CRC 用 crypto.crc16_modbus 校验。
     （另提供 rs485_dir_mode="auto" 走 uart.setup 硬件自动换向，便于对照测试。）

对外接口（与旧版完全一致，调用方无需改动）：
     modbus_master.setup()             -- 初始化（485 供电 + 串口 + 回调）
     modbus_master.read_reg(reg)       -- 读单个保持寄存器（03），返回原始值或 nil
     modbus_master.write_reg(reg,val)  -- 写单个保持寄存器（06），返回 boolean

⚠️ read_reg / write_reg 内部会挂起（sys.wait / sys.waitUntil），
   必须由协程（sys.taskInit 任务）调用；禁止在 sys.subscribe 回调里直接调用。

依据：requirement.md 5.2/5.9、inter-device-communication-protocol.md、嵌入式软件总体设计.md。
本模块有对外接口，末尾 return M。
]]

local config_app = require("config_app")

local M = {}

-- 串口编号（UART2）
local UART_ID = config_app.uart_id

-- 接收缓冲：串口收到的原始字节累积于此
local rx_buf = ""
-- 发送完成标志（"sent" 事件置位）
local tx_done = false
-- 总线互斥锁：避免采集读与下行写并发使用 485 总线
local busy = false

--[[
串口接收回调：把当前可读数据全部读入 rx_buf
]]
local function on_receive(uart_id, data_len)
    while true do
        local data = uart.read(uart_id, data_len)
        if not data or #data == 0 then
            return
        end
        rx_buf = rx_buf .. data
    end
end

--[[
串口发送完成回调：
1. 手动方向模式下立即把方向脚切回接收态——尽量缩短"发送态"占用总线的时间，
   避免变频器应答很快时被发送器挡住而整帧错过；
2. 置位发送完成标志；
3. 发布事件，唤醒 transact 继续收帧。
]]
local function on_sent(uart_id)
    if config_app.rs485_dir_mode == "manual" then
        gpio.setup(config_app.pin_485_dir, 0)
    end
    tx_done = true
    sys.publish("MB_TX_DONE")
end

--[[
加锁：获取 485 总线使用权（协作式调度，检查与置位之间无让出，安全）
]]
local function lock()
    while busy do
        sys.wait(5)
    end
    busy = true
end

--[[
解锁：释放 485 总线使用权
]]
local function unlock()
    busy = false
end

--[[
计算并追加 CRC16(Modbus)（低字节在前）
]]
local function append_crc(frame)
    local crc = crypto.crc16_modbus(frame)
    return frame .. string.char(crc & 0xFF, (crc >> 8) & 0xFF)
end

--[[
校验帧末尾 CRC（低字节在前）
@return boolean 校验是否通过
]]
local function check_crc(frame)
    if #frame < 4 then
        return false
    end
    local calc = crypto.crc16_modbus(frame:sub(1, -3))
    local recv = string.byte(frame, -2) + string.byte(frame, -1) * 256
    return calc == recv
end

--[[
接收一帧：等待首字节到达后，连续静默 20ms 视为一帧结束
@param timeout_ms number 整体超时（ms）
@return string|nil 收到的帧；超时返回 nil
]]
local function recv_frame(timeout_ms)
    local waited = 0
    -- 等待首字节
    while #rx_buf == 0 and waited < timeout_ms do
        sys.wait(5)
        waited = waited + 5
    end
    if #rx_buf == 0 then
        return nil
    end
    -- 静默判帧：只要有新字节就重置静默计数
    local last = 0
    local silent = 0
    while silent < 20 and waited < timeout_ms do
        sys.wait(5)
        waited = waited + 5
        if #rx_buf ~= last then
            last = #rx_buf
            silent = 0
        else
            silent = silent + 5
        end
    end
    local frame = rx_buf
    rx_buf = ""
    return frame
end

--[[
一次完整收发：进入发送态 → 发送 → 等发送完成 → 回接收态 → 收帧
@param frame string 待发送的完整帧（含 CRC）
@param timeout_ms number 等待应答超时（ms）
@return string|nil 应答帧；失败返回 nil
]]
local function transact(frame, timeout_ms)
    rx_buf = ""
    tx_done = false

    -- 1. 进入发送态（仅手动方向模式；auto 模式由 uart 硬件自动换向）
    if config_app.rs485_dir_mode == "manual" then
        gpio.setup(config_app.pin_485_dir, 1)
    end
    -- 2. 发送
    uart.write(UART_ID, frame)
    if config_app.modbus_debug then
        log.info("modbus_master", "TX", frame:toHex())
    end
    -- 3. 等发送完成：事件驱动（回调里已立即切回接收态）；最多等 50ms 兜底
    sys.waitUntil("MB_TX_DONE", 50)
    if config_app.rs485_dir_mode == "manual" then
        gpio.setup(config_app.pin_485_dir, 0) -- 兜底：确保处于接收态
    end

    -- 4. 收帧
    local resp = recv_frame(timeout_ms)
    if config_app.modbus_debug then
        log.info("modbus_master", "RX", resp and resp:toHex() or "nil")
    end
    return resp
end

--[[
初始化 485 与串口
@return boolean 是否成功
]]
function M.setup()
    -- 485 收发器供电使能：必须开机拉高，否则收发器无供电、总线无输出
    gpio.setup(config_app.pin_485_pwr, 1)
    -- 方向脚：空闲置于接收态
    gpio.setup(config_app.pin_485_dir, config_app.rs485_dir_rx_level)

    -- 串口初始化：
    --   manual 模式：不传方向脚，关闭硬件自动换向（方向由本模块手动控制）；
    --   auto   模式：把方向脚交给 uart.setup 自动换向（rs485_dir_gpio + rs485_level）。
    local ret
    if config_app.rs485_dir_mode == "auto" then
        ret = uart.setup(UART_ID, config_app.baud_rate, config_app.data_bits,
            config_app.stop_bits, uart.None, uart.LSB, 1024,
            config_app.pin_485_dir, config_app.rs485_dir_rx_level)
    else
        ret = uart.setup(UART_ID, config_app.baud_rate, config_app.data_bits,
            config_app.stop_bits, uart.None, uart.LSB, 1024)
    end
    if ret ~= 0 then
        log.error("modbus_master", "UART 初始化失败", UART_ID, ret)
        return false
    end

    uart.on(UART_ID, "receive", on_receive)
    uart.on(UART_ID, "sent", on_sent)

    log.info("modbus_master", "RTU 主站初始化成功", "mode", config_app.rs485_dir_mode,
        "uart", UART_ID, "dir", config_app.pin_485_dir, "rx_level", config_app.rs485_dir_rx_level,
        "pwr", config_app.pin_485_pwr, "debug", config_app.modbus_debug)
    return true
end

--[[
读取单个保持寄存器（03 功能码）
@param reg number 寄存器地址
@return number|nil 寄存器原始值，失败返回 nil
]]
function M.read_reg(reg)
    lock()
    local frame = append_crc(string.char(config_app.slave_id, 0x03,
        (reg >> 8) & 0xFF, reg & 0xFF, 0x00, 0x01))
    local resp = transact(frame, config_app.modbus_timeout)
    unlock()

    if not resp then
        return nil
    end
    if not check_crc(resp) then
        log.warn("modbus_master", "读寄存器 CRC 校验失败", reg, resp:toHex())
        return nil
    end
    local addr = string.byte(resp, 1)
    local func = string.byte(resp, 2)
    if addr ~= config_app.slave_id then
        return nil
    end
    if func == 0x83 then
        log.warn("modbus_master", "读寄存器异常响应", reg, "excp", string.byte(resp, 3))
        return nil
    end
    if func ~= 0x03 or #resp < 7 then
        return nil
    end
    return string.byte(resp, 4) * 256 + string.byte(resp, 5)
end

--[[
写入单个保持寄存器（06 功能码）
@param reg number 寄存器地址
@param value number 写入值
@return boolean 是否成功
]]
function M.write_reg(reg, value)
    lock()
    local frame = append_crc(string.char(config_app.slave_id, 0x06,
        (reg >> 8) & 0xFF, reg & 0xFF, (value >> 8) & 0xFF, value & 0xFF))
    local resp = transact(frame, config_app.modbus_timeout)
    unlock()

    if not resp then
        return false
    end
    -- 06 应答为请求帧原样回显
    if resp == frame then
        return true
    end
    if not check_crc(resp) then
        log.warn("modbus_master", "写寄存器 CRC 校验失败", reg, resp:toHex())
        return false
    end
    if string.byte(resp, 2) == 0x86 then
        log.warn("modbus_master", "写寄存器异常响应", reg, "excp", string.byte(resp, 3))
    end
    return false
end

return M
