--[[
@module  drv_modbus
@summary Modbus RTU 主机驱动（功能码 03，只读）
@version 1.0.0
@date    2026.11.16

设计说明：
1. 485 方向（DE）由 uart.setup 的 pin485 参数交给平台自动换向，Lua 侧不碰方向脚；
2. 收包靠 uart.on("receive") 回调累积，主循环只等一个常驻的 10ms 心跳事件，
   不用 sys.wait(ms) / sys.waitUntil(msg, ms) 做超时——那两种写法每帧都会创建
   并销毁一个 C 层定时器，在这颗芯片上有概率丢唤醒，表现为整帧收不到或读到残段；
3. 平台首次写出的帧在总线上无效（PLC 不回，第二帧起正常），初始化时先发一帧哑请求
   把"第一帧"消耗掉；
4. 纯只读：只发功能码 03，绝不写寄存器。
]]
local M = {}

local conf = require "conf"

local cfg = conf.uart
local buf = {}
local rx_len = 0
local opened = false
local started = false

-- ===== CRC16 (Modbus) =====
local function crc16(s)
    local crc = 0xFFFF
    for i = 1, #s do
        crc = crc ~ s:byte(i)
        for _ = 1, 8 do
            if crc & 1 ~= 0 then
                crc = (crc >> 1) ~ 0xA001
            else
                crc = crc >> 1
            end
        end
    end
    return crc & 0xFFFF
end

--[[
字节串转十六进制文本，用于日志
@param s string 原始字节
@return string 形如 "CC 03 1A 2C"
]]
local function tohex(s)
    if not s or #s == 0 then
        return "--"
    end
    local t = {}
    for i = 1, #s do
        t[i] = string.format("%02X", s:byte(i))
    end
    return table.concat(t, " ")
end

-- 收发报文日志：一行显示一问一答，便于对着看
local function log_frame(tx, rx, note)
    if conf.log_frames == false then
        return
    end
    if note then
        log.info("modbus", "TX[" .. tx .. "]  RX[" .. rx .. "]", note)
    else
        log.info("modbus", "TX[" .. tx .. "]  RX[" .. rx .. "]")
    end
end

local function with_crc(s)
    local c = crc16(s)
    return s .. string.char(c & 0xFF, (c >> 8) & 0xFF)
end

-- ===== 收包 =====
local function on_receive(id)
    local d = uart.read(id, 2048)
    if d and #d > 0 then
        buf[#buf + 1] = d
        rx_len = rx_len + #d
    end
end

local function flush()
    buf = {}
    rx_len = 0
    pcall(uart.read, cfg.id, 2048)   -- 清掉残留
end

-- 等 n 个心跳（每个 10ms）
local function wait_ticks(n)
    for _ = 1, n do
        sys.waitUntil("MB_TICK")
    end
end

-- 常驻心跳：只创建一次，从不删除
local function start_tick()
    if started then return end
    started = true
    sys.timerLoopStart(function()
        sys.publish("MB_TICK")
    end, 10)
end

--[[
打开串口
@return boolean, string|nil
]]
function M.init()
    start_tick()

    local r = uart.setup(cfg.id, cfg.baud, cfg.databits, cfg.stopbits, cfg.parity,
        uart.LSB, 2048, cfg.de_pin, cfg.de_rx_level, cfg.rs485_delay_us, nil, 0)
    if r ~= 0 then
        return false, "uart.setup 失败，返回 " .. tostring(r)
    end

    -- 硬件就绪需要时间
    wait_ticks(10)

    uart.on(cfg.id, "receive", on_receive)
    opened = true

    -- 消耗掉平台的第一帧（这帧通常收不到应答，属于正常）
    M.read_raw(conf.plc.slave, conf.plc.reg, conf.plc.count)
    flush()

    return true
end

--[[
一次收发：发出帧，等够 need 字节，返回原始字节串
@param frame string 完整帧
@param need number 期望收到的字节数
@return string|nil, string|nil
]]
local function xfer(frame, need)
    flush()
    uart.write(cfg.id, frame)

    local timeout_ticks = math.ceil(conf.plc.timeout / 10)
    local waited = 0
    -- 正常应答 need 字节；异常应答固定 5 字节，凑够就先收下
    while rx_len < need and rx_len ~= 5 and waited < timeout_ticks do
        wait_ticks(1)
        waited = waited + 1
    end

    if rx_len == 0 then
        return nil, "超时"
    end
    return table.concat(buf)
end

-- 判断 8 个数据字节是不是全 0
local function data_all_zero(b, count)
    for i = 4, 3 + count * 2 do
        if b[i] ~= 0 then
            return false
        end
    end
    return true
end

--[[
一次收发：发出帧，等够 need 字节，返回原始字节串
@param frame string 完整帧
@param need number 期望收到的字节数
@return string|nil, string|nil
]]
local function xfer(frame, need)
    flush()
    uart.write(cfg.id, frame)

    local timeout_ticks = math.ceil(conf.plc.timeout / 10)
    local waited = 0
    -- 正常应答 need 字节；异常应答固定 5 字节，凑够就先收下
    while rx_len < need and rx_len ~= 5 and waited < timeout_ticks do
        wait_ticks(1)
        waited = waited + 1
    end

    if rx_len == 0 then
        return nil, "超时"
    end
    return table.concat(buf)
end

-- 判断数据字节是不是全 0
local function data_all_zero(b, count)
    for i = 4, 3 + count * 2 do
        if b[i] ~= 0 then
            return false
        end
    end
    return true
end

--[[
发一帧 03 读寄存器，返回原始寄存器数组（1 起）
@param slave number 从站地址
@param start number 起始寄存器
@param count number 寄存器个数
@return table|nil, string|nil

设计原则：收到什么就是什么，不做重读、不做替换。
数据全零是真实异常（输入悬空 / AD 未采样），如实往上报：
日志标注「数据全零」，数值照常交给上层，由报警逻辑判成「断线」并记录。
]]
function M.read_raw(slave, start, count)
    if not opened then
        return nil, "串口未打开"
    end

    local body = string.char(slave, 0x03,
        (start >> 8) & 0xFF, start & 0xFF,
        (count >> 8) & 0xFF, count & 0xFF)
    local frame = with_crc(body)
    local tx_hex = tohex(frame)
    local need = 3 + count * 2 + 2

    local raw, err = xfer(frame, need)
    if not raw then
        log_frame(tx_hex, "--", err)
        return nil, err
    end

    local rx_hex = tohex(raw)
    local b = { raw:byte(1, -1) }

    local bad
    if b[1] ~= slave then
        bad = string.format("站号不符 %d", b[1] or -1)
    elseif b[2] == 0x83 then
        bad = string.format("从站异常码 %d（寄存器越界？）", b[3] or -1)
    elseif b[2] ~= 0x03 then
        bad = string.format("功能码异常 0x%02X", b[2] or 0)
    elseif #b < need then
        bad = string.format("应答不完整 %d/%d", #b, need)
    else
        local c = crc16(raw:sub(1, need - 2))
        if (c & 0xFF) ~= b[need - 1] or ((c >> 8) & 0xFF) ~= b[need] then
            bad = "CRC 校验错"
        end
    end

    if bad then
        log_frame(tx_hex, rx_hex, bad)
        return nil, bad
    end

    -- 全零不是错误帧，是可疑数据：照收，但在日志里标出来
    log_frame(tx_hex, rx_hex, data_all_zero(b, count) and "数据全零" or nil)

    local regs = {}
    for i = 0, count - 1 do
        regs[i + 1] = (b[4 + i * 2] << 8) | b[5 + i * 2]
    end
    return regs
end

--[[
两个寄存器拼成单精度浮点
@param hi number 第一个寄存器
@param lo number 第二个寄存器
@param swap boolean true = CDAB（低字在前）
@return number
]]
function M.regs_to_float(hi, lo, swap)
    local w1, w2 = hi, lo
    if swap then w1, w2 = lo, hi end
    local s = string.char((w1 >> 8) & 0xFF, w1 & 0xFF, (w2 >> 8) & 0xFF, w2 & 0xFF)
    local ok, v = pcall(string.unpack, ">f", s)
    if ok then return v end
    return 0
end

function M.close()
    if opened then
        pcall(uart.on, cfg.id, "receive", nil)
        opened = false
    end
end

return M
