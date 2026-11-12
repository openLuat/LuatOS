--[[
@module  drv_modbus
@summary Modbus RTU 主站（RS485 半双工），只实现本工程需要的 03 读 / 06 写
@version 1.0.0
@date    2026.11.12

=== 帧结构 ===
请求（03 读保持寄存器）
    站号(1) 03 起始地址Hi 起始地址Lo 数量Hi 数量Lo CRC_Lo CRC_Hi
响应
    站号(1) 03 字节数(1) 数据(2N) CRC_Lo CRC_Hi
请求（06 写单寄存器）
    站号(1) 06 地址Hi 地址Lo 值Hi 值Lo CRC_Lo CRC_Hi
响应：原样回显请求帧
异常响应
    站号(1) 功能码|0x80 异常码(1) CRC_Lo CRC_Hi

=== CRC ===
Modbus CRC16：初值 0xFFFF，多项式 0xA001（反向），低位先算，结果低字节在前。
注意与三菱的累加和完全不同，不能混用。

=== 平台适配（沿用 melsec_hmi/drv_fxlinks 的结论）===
1. 485 方向脚由 uart.setup 的 pin485 参数交给平台自动换向，Lua 侧不碰方向脚；
2. 收发等待不能用 sys.wait(ms)：每次调用都会新建/销毁 C 层定时器，
   在 SDK 的定时器删除窗口里会丢唤醒（表现为整帧丢或读到残段）。
   改用常驻 10ms 循环定时器发布统一事件，收发全程只等这一个事件；
3. 平台首次写出的帧在总线上无效，初始化时先发一帧哑请求消耗掉，
   否则每次开机第一帧都会超时。
]]

local M = {}

local cfg, modbus
local rx = {}
local opened = false
local busy = false
local first_station          -- 第一台电机站号，仅用于初始化时消耗平台首个无效帧

local TICK_MS = 10
local TICK_EVT = "MB_TICK"
local tick_id
local tx_waiting = false

-- ===== CRC16 =====

--[[
计算 Modbus CRC16
@param s string 待计算数据（不含 CRC 本身）
@return number 0~65535
]]
local function crc16(s)
    local crc = 0xFFFF
    for i = 1, #s do
        crc = crc ~ s:byte(i)
        for _ = 1, 8 do
            if crc & 1 == 1 then
                crc = (crc >> 1) ~ 0xA001
            else
                crc = crc >> 1
            end
        end
    end
    return crc & 0xFFFF
end

--[[
附加 CRC 到帧尾（低字节在前）
@param body string 不含 CRC 的帧
@return string 完整帧
]]
local function with_crc(body)
    local c = crc16(body)
    return body .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

--[[
校验一帧的 CRC
@param frame string 含 CRC 的完整帧
@return boolean
]]
local function check_crc(frame)
    if #frame < 4 then return false end
    local body = frame:sub(1, #frame - 2)
    local got = frame:byte(#frame - 1) | (frame:byte(#frame) << 8)
    return got == crc16(body)
end

--[[
原始字节转十六进制字符串，便于日志排查
@param s string
@return string
]]
function M.hex(s)
    if not s or #s == 0 then return "" end
    return (string.gsub(s, ".", function(ch)
        return string.format("%02X ", ch:byte())
    end))
end

-- ===== 组帧 =====

--[[
构造 03 读保持寄存器请求
@param station number 站号 1~254
@param addr number 起始寄存器地址
@param count number 寄存器数量
@return string
]]
function M.build_read(station, addr, count)
    local body = string.char(station, 0x03,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (count >> 8) & 0xFF, count & 0xFF)
    return with_crc(body)
end

--[[
构造 06 写单寄存器请求
@param station number 站号
@param addr number 寄存器地址
@param value number 写入值（16 位）
@return string
]]
function M.build_write(station, addr, value)
    local body = string.char(station, 0x06,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (value >> 8) & 0xFF, value & 0xFF)
    return with_crc(body)
end

-- ===== 心跳 =====

local function tick_start()
    if tick_id then return end
    tick_id = sys.timerLoopStart(function()
        sys.publish(TICK_EVT)
    end, TICK_MS)
end

local function tick_stop()
    if tick_id then
        sys.timerStop(tick_id)
        tick_id = nil
    end
end

local function on_sent()
    tx_waiting = false
    sys.publish(TICK_EVT)
end

local function on_receive(uid, len)
    local d = uart.read(uid, len)
    if d and #d > 0 then
        rx[#rx + 1] = d
        sys.publish(TICK_EVT)
    end
end

--[[
判断缓冲区里是否已组成完整响应帧
@param s string 累积数据
@return number >0 帧长；0 未收完；-1 首字节非法
]]
local function frame_len(s)
    if #s < 2 then return 0 end

    local fc = s:byte(2)

    -- 异常响应：站号 功能码|0x80 异常码 CRC(2) = 5 字节
    if fc & 0x80 ~= 0 then
        return #s >= 5 and 5 or 0
    end

    if fc == 0x03 then
        -- 正常读响应：站号 03 字节数 数据 CRC(2)
        if #s < 3 then return 0 end
        local total = 3 + s:byte(3) + 2
        return #s >= total and total or 0
    elseif fc == 0x06 then
        -- 写响应：原样回显 8 字节
        return #s >= 8 and 8 or 0
    end

    return -1
end

-- ===== 串口 =====

--[[
初始化串口
@param c table conf.uart
@param m table conf.modbus
@return boolean ok, string|nil err
]]
function M.init(c, m)
    cfg, modbus = c, m

    local r = uart.setup(cfg.id, cfg.baud, cfg.databits, cfg.stopbits, cfg.parity,
        uart.LSB, 1024, cfg.de_pin, cfg.de_rx_level, cfg.rs485_delay_us, nil, 0)
    if r ~= 0 then
        return false, "uart.setup 失败，返回 " .. tostring(r)
    end

    sys.wait(100)

    uart.on(cfg.id, "receive", on_receive)
    uart.on(cfg.id, "sent", on_sent)
    opened = true
    tick_start()

    -- 消耗平台的第一帧（首次写出的帧在总线上无效）
    if first_station then
        uart.write(cfg.id, M.build_read(first_station, 0x2100, 1))
        sys.wait(150)
        uart.read(cfg.id, 2048)
    end

    log.info("modbus", "串口已打开", cfg.baud,
        cfg.databits .. "位", "无校验", cfg.stopbits .. "停止位",
        "DE=GPIO" .. tostring(cfg.de_pin) .. "(自动换向)")
    return true
end

--[[
登记第一台电机站号（必须在 M.init 之前调用）
@param st number
]]
function M.set_first_station(st)
    first_station = st
end

--[[
关闭串口
]]
function M.close()
    if not opened then return end
    uart.on(cfg.id, "receive", nil)
    uart.on(cfg.id, "sent", nil)
    uart.close(cfg.id)
    tick_stop()
    opened = false
end

-- ===== 收发 =====

local function transact_inner(frame)
    rx = {}
    uart.read(cfg.id, 2048)

    tx_waiting = true
    local n = uart.write(cfg.id, frame)
    if not n or n <= 0 then
        tx_waiting = false
        return nil, "串口写入失败"
    end

    -- 等发送交清：8N1 每字节 10 位
    local tx_ms = math.ceil(#frame * 10 * 1000 / cfg.baud)
    local tx_ticks = math.max(1, math.ceil((tx_ms + 8) / TICK_MS))
    for _ = 1, tx_ticks do
        if not tx_waiting then break end
        sys.waitUntil(TICK_EVT)
    end
    tx_waiting = false

    local max_idle = math.ceil(modbus.timeout / TICK_MS)
    local idle = 0
    local last_n = -1

    while idle <= max_idle do
        local data = table.concat(rx)
        local len = frame_len(data)

        if len > 0 then
            rx = {}
            return data:sub(1, len)
        elseif len < 0 then
            rx = {}
            return nil, "响应错乱：" .. M.hex(data:sub(1, 8))
        end

        if #data ~= last_n then
            last_n = #data
            idle = 0
        else
            idle = idle + 1
        end

        sys.waitUntil(TICK_EVT)
    end

    return nil, string.format("响应超时（收到 %d 字节）", #table.concat(rx))
end

local BUSY_TIMEOUT = 1500   -- 等总线释放的最长时间 ms

local function transact(frame)
    if not opened then return nil, "串口未打开" end

    -- 轮询任务可能正占用总线。这里等它释放，而不是直接失败：
    -- 直接失败会让"按停止"偶发无效——轮询每 500ms 一次，窗口很小但确实存在。
    local waited = 0
    while busy do
        if waited >= BUSY_TIMEOUT then
            return nil, "串口忙（等待超时）"
        end
        sys.waitUntil(TICK_EVT)
        waited = waited + TICK_MS
    end

    busy = true
    local ok, a, b = pcall(transact_inner, frame)
    busy = false

    if not ok then
        return nil, "内部异常：" .. tostring(a)
    end
    return a, b
end

--[[
校验并解析响应
@param raw string 完整响应帧
@param station number 期望站号
@return table { ok=true, ... } 或 { ok=false, err="..." }
]]
local function parse(raw, station)
    if not check_crc(raw) then
        return { ok = false, err = "CRC 错误：" .. M.hex(raw) }
    end

    if raw:byte(1) ~= station then
        return { ok = false,
            err = string.format("站号不匹配：回 %d，期望 %d", raw:byte(1), station) }
    end

    local fc = raw:byte(2)

    if fc & 0x80 ~= 0 then
        return { ok = false,
            err = string.format("从站异常码 %d", raw:byte(3)),
            exception = raw:byte(3) }
    end

    return { ok = true, fc = fc }
end

-- ===== 对外 API =====

--[[
读保持寄存器（功能码 03）
@param station number 站号
@param addr number 起始地址
@param count number 数量 1~16
@return table|nil 数值数组（1 起）, string|nil 错误
]]
function M.read_regs(station, addr, count)
    count = count or 1
    if count < 1 or count > 16 then
        return nil, "数量需 1~16"
    end

    local frame = M.build_read(station, addr, count)
    local raw, err = transact(frame)
    if not raw then
        log.warn("modbus", "读无响应", M.hex(frame), err)
        return nil, err
    end

    local r = parse(raw, station)
    if not r.ok then
        log.warn("modbus", "读失败", M.hex(raw), r.err)
        return nil, r.err
    end

    -- 响应结构：站号(1) 03 字节数(1) 数据... CRC(2)
    -- 数据从第 4 个字节开始，第 3 个字节是字节数，不能当数据取
    if #raw < 3 + count * 2 + 2 then
        return nil, "数据长度不足"
    end

    local out = {}
    for i = 1, count do
        local hi = raw:byte(4 + (i - 1) * 2)
        local lo = raw:byte(5 + (i - 1) * 2)
        out[i] = (hi << 8) | lo
    end
    return out
end

--[[
写单个寄存器（功能码 06）
@param station number 站号
@param addr number 地址
@param value number 值
@return boolean|nil 成功, string|nil 错误
]]
function M.write_reg(station, addr, value)
    local frame = M.build_write(station, addr, value)
    local raw, err = transact(frame)
    if not raw then
        log.warn("modbus", "写无响应", M.hex(frame), err)
        return nil, err
    end

    local r = parse(raw, station)
    if not r.ok then
        log.warn("modbus", "写失败", M.hex(raw), r.err)
        return nil, r.err
    end

    return true
end

return M
