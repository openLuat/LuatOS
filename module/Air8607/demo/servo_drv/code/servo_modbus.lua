--[[
@module  servo_modbus
@summary 伺服驱动器 Modbus-RTU 主站（最小实现）+ LW-XP 寄存器映射
@version 1.0
@date    2026.11.02

【独立模块】与 servo_pulse / main.lua 完全解耦：
  main.lua 当前只做「脉冲 + 方向」测试，不会加载本文件；
  需要单独验证 485 时，在脚本里 require "servo_modbus" 并先把 conf.mb.enable 改成 true。

只实现本测试用得到的部分：
  0x03 读多个寄存器 / 0x06 写单个寄存器，CRC16(MODBUS)，低字节在前。
地址定义见 docs/MODBUS 通讯地址（总）.pdf 与说明书 6.3.9 节：
  Pn 组首地址 0x0000（Pn001=0x0001，Pn008=0x0008，…）
  Un 组首地址 0x2000（Un000=0x2000，Un020=0x2014，…）
  32bit 参数占 2 个连续寄存器，默认高字在前（conf.mb.hi_word_first）
]]
local M = {}

local conf = require "conf"
local MB = conf.mb

local EVT = "SERVO_MB_RX"
local uart_id
local rx_buf = ""
local inited = false
local busy = false

-- 用到的寄存器地址
M.REG = {
    P_CTRL_MODE = 0x0001, -- Pn001 控制模式（0=位置）
    P_DIR_REV   = 0x0006, -- Pn006 位置模式方向取反
    P_PULSE_FMT = 0x0007, -- Pn007 外部脉冲指令输入形式（3=符号+脉冲）
    P_PULSE_REV = 0x0008, -- Pn008 电机旋转 1 圈的指令脉冲数（32bit）
    P_STATION   = 0x0600, -- Pn600 站号

    U_SPEED     = 0x2000, -- Un000 电机转速 rpm（有符号）
    U_POS_DEV   = 0x2010, -- Un016 位置偏差（32bit）
    U_POS_CMD   = 0x2014, -- Un020 伺服当前位置（指令脉冲单位，32bit）
    U_POS_ENC   = 0x2016, -- Un022 伺服当前位置（编码器单位，32bit）
    U_LOAD      = 0x201B, -- Un027 电机负载率
    U_DI_STATE  = 0x2020, -- Un032 DI 输入状态
    U_DO_STATE  = 0x201F, -- Un031 DO 输出状态
    U_ENABLE    = 0x203A, -- Un058 伺服使能状态

    -- 报警码：说明书 6.3.9 的「状态显示组」首地址 0x3E00。
    -- 该组未在《MODBUS 通讯地址（总）.pdf》里列出，读不到属正常现象，
    -- 报警信息以面板显示为准（E13/E15/E16 等见说明书第 5 章）。
    ALARM       = 0x3E00,
}

-- ==================== 基础工具 ====================

local function crc16(s)
    local crc = 0xFFFF
    for i = 1, #s do
        crc = crc ~ s:byte(i)
        for _ = 1, 8 do
            if (crc & 1) == 1 then
                crc = (crc >> 1) ~ 0xA001
            else
                crc = crc >> 1
            end
        end
    end
    return crc & 0xFF, (crc >> 8) & 0xFF
end

local function now_ms()
    if mcu and mcu.hz and mcu.ticks then
        local hz = mcu.hz()
        if hz and hz > 1 then
            return mcu.ticks() * 1000 // hz
        end
        return mcu.ticks()
    end
    return 0
end

local function s16(v)
    if v >= 0x8000 then return v - 0x10000 end
    return v
end

local function s32(v)
    if v >= 0x80000000 then return v - 0x100000000 end
    return v
end

--[[从接收缓存里找一帧完整且 CRC 正确的应答（容忍 485 半双工回显）]]
local function pick_frame(buf)
    for i = 1, #buf - 4 do
        if buf:byte(i) == MB.slave then
            local fc = buf:byte(i + 1)
            local total
            if fc == 0x03 then
                total = (buf:byte(i + 2) or 0) + 5
            elseif fc == 0x06 then
                total = 8
            elseif (fc & 0x80) ~= 0 then
                total = 5
            end
            if total and (i + total - 1) <= #buf then
                local part = buf:sub(i, i + total - 1)
                local lo, hi = crc16(part)
                if part:byte(-2) == lo and part:byte(-1) == hi then
                    return part
                end
            end
        end
    end
    return nil
end

--[[发一帧并等应答，返回原始应答帧]]
local function transact(body)
    if not inited then return nil, "485 未初始化" end
    if busy then return nil, "总线忙" end
    busy = true

    local adu = string.char(MB.slave) .. body
    local lo, hi = crc16(adu)
    adu = adu .. string.char(lo, hi)

    rx_buf = ""
    uart.write(uart_id, adu)
    -- 等最后一个字节移出移位寄存器：11bit/字节 + 余量
    sys.wait(math.ceil(#adu * 11 * 1000 / MB.baud) + 2)

    local f
    local t0 = now_ms()
    while true do
        f = pick_frame(rx_buf)
        if f then break end
        if now_ms() - t0 >= MB.timeout then break end
        sys.waitUntil(EVT, 5)
    end
    busy = false

    if not f then return nil, "应答超时" end
    local fc = f:byte(2)
    if (fc & 0x80) ~= 0 then
        return nil, string.format("异常码 0x%02X", f:byte(3) or 0)
    end
    return f
end

-- ==================== 对外接口 ====================

--[[初始化 485 串口（并做一次探活）
@return boolean, string
]]
function M.init()
    if not MB.enable then
        log.info("mb", "conf.mb.enable = false，跳过 485")
        return false, "disabled"
    end
    uart_id = MB.uart_id

    local par = uart.NONE
    if MB.parity == "even" then
        par = uart.EVEN
    elseif MB.parity == "odd" then
        par = uart.ODD
    end

    local ret
    if MB.rs485_dir_gpio then
        ret = uart.setup(uart_id, MB.baud, 8, MB.stop_bits or 1, par,
            uart.LSB, 1024, MB.rs485_dir_gpio, MB.rs485_rx_level or 0, 2000)
    else
        ret = uart.setup(uart_id, MB.baud, 8, MB.stop_bits or 1, par)
    end
    if ret ~= 0 then
        return false, "uart.setup 失败(" .. tostring(ret) .. ")"
    end

    uart.on(uart_id, "receive", function(id, len)
        local d = uart.read(id, len)
        if d and #d > 0 then rx_buf = rx_buf .. d end
        sys.publish(EVT)
    end)

    inited = true
    local par_txt = (MB.parity == "even") and "E" or (MB.parity == "odd") and "O" or "N"
    log.info("mb", string.format("uart%d %d 8%s%d 站号%d 就绪",
        uart_id, MB.baud, par_txt, MB.stop_bits or 1, MB.slave))

    local regs = M.read(M.REG.U_ENABLE, 1) -- 探活
    if not regs then
        return false, "驱动器无应答"
    end
    return true
end

function M.available()
    return inited
end

--[[读多个寄存器
@return table|nil, string 寄存器数组（16bit 无符号）
]]
function M.read(addr, count)
    local f, err = transact(string.char(0x03,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (count >> 8) & 0xFF, count & 0xFF))
    if not f then return nil, err end
    if f:byte(2) ~= 0x03 then return nil, "功能码不符" end

    local n = f:byte(3) or 0
    local regs = {}
    for i = 1, n // 2 do
        regs[i] = ((f:byte(i * 2 + 3) or 0) << 8) | (f:byte(i * 2 + 4) or 0)
    end
    return regs
end

--[[读 32bit（占 2 个寄存器），按有符号返回]]
function M.read32(addr)
    local regs = M.read(addr, 2)
    if not regs or #regs < 2 then return nil end
    local v
    if MB.hi_word_first then
        v = (regs[1] << 16) | regs[2]
    else
        v = (regs[2] << 16) | regs[1]
    end
    return s32(v)
end

--[[写单个寄存器（0x06）]]
function M.write(addr, value)
    value = math.floor(value) & 0xFFFF
    local f, err = transact(string.char(0x06,
        (addr >> 8) & 0xFF, addr & 0xFF,
        (value >> 8) & 0xFF, value & 0xFF))
    if not f then return false, err end
    return true
end

--[[当前位置（指令脉冲单位），失败返回 nil]]
function M.get_position()
    return M.read32(M.REG.U_POS_CMD)
end

--[[读一组状态，全失败返回 nil
@return table {pos, speed, dev, load, enabled, di, do, alarm}
]]
function M.read_status()
    local st = {}
    local regs

    st.pos = M.read32(M.REG.U_POS_CMD)

    regs = M.read(M.REG.U_SPEED, 1)
    st.speed = regs and s16(regs[1]) or nil

    st.dev = M.read32(M.REG.U_POS_DEV)

    regs = M.read(M.REG.U_LOAD, 1)
    st.load = regs and regs[1] or nil

    regs = M.read(M.REG.U_ENABLE, 1)
    st.enabled = regs and regs[1] or nil

    regs = M.read(M.REG.U_DI_STATE, 1)
    st.di = regs and regs[1] or nil

    regs = M.read(M.REG.U_DO_STATE, 1)
    st.do_ = regs and regs[1] or nil

    regs = M.read(M.REG.ALARM, 1) -- 读不到不影响其它项
    st.alarm = regs and regs[1] or nil

    if st.pos == nil and st.speed == nil and st.enabled == nil then
        return nil
    end
    return st
end

--[[打印驱动器关键参数，用来确认脉冲设置对不对]]
function M.dump_params()
    local function one(name, addr)
        local regs = M.read(addr, 1)
        local v = regs and regs[1] or nil
        log.info("mb", string.format("%s = %s", name, v == nil and "读取失败" or tostring(v)))
        return v
    end

    local mode = one("Pn001 控制模式(0=位置)", M.REG.P_CTRL_MODE)
    if mode and mode ~= 0 then
        log.warn("mb", "Pn001 不是 0，驱动器不在位置控制模式，脉冲指令无效")
    end

    one("Pn006 方向取反(0/1)", M.REG.P_DIR_REV)

    local fmt = one("Pn007 脉冲形式(3=方向+脉冲)", M.REG.P_PULSE_FMT)
    if fmt and fmt ~= 3 then
        log.warn("mb", "Pn007 不是 3，请改成 3 后重新上电，否则脉冲/方向不匹配")
    end

    local ppr = M.read32(M.REG.P_PULSE_REV)
    if ppr then
        log.info("mb", string.format("Pn008 每圈指令脉冲数 = %d", ppr))
        if ppr ~= conf.servo.pulses_per_rev then
            log.warn("mb", string.format("Pn008(%d) 与 conf.servo.pulses_per_rev(%d) 不一致，速度换算会偏",
                ppr, conf.servo.pulses_per_rev))
        end
    else
        log.warn("mb", "Pn008 读取失败")
    end
end

--[[打印一组运行状态]]
function M.dump_status()
    local st = M.read_status()
    if not st then
        log.warn("mb", "状态读取失败（485 无应答）")
        return nil
    end
    log.info("mb", string.format(
        "转速=%s rpm 位置=%s 偏差=%s 负载=%s 使能=%s DI=0x%04X DO=0x%04X 报警=%s",
        tostring(st.speed), tostring(st.pos), tostring(st.dev), tostring(st.load),
        tostring(st.enabled), st.di or 0, st.do_ or 0, tostring(st.alarm)))
    if st.enabled == 0 then
        log.warn("mb", "伺服未使能(Un058=0)：脉冲发出去电机也不会转，请检查 S-ON/DI 接线")
    end
    return st
end

return M
