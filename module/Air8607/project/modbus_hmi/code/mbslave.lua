--[[
@module  mbslave
@summary 内置 Modbus 虚拟从站：5 个从站的寄存器库 + 现场过程模拟 + 故障注入
@version 1.0.0
@date    2026.10.25

用途：
  1、PC 模拟器 / 未接 RS485 总线时，为本机的 Modbus 主站提供"真实"的从站响应；
     主站侧走的是完整协议（组帧 → CRC → 超时 → 解析 → 异常码），与真机完全一致；
  2、演示闭环控制：主站写设定值（0x06 / 0x05）后，过程模拟会跟随该设定值变化；
  3、故障注入：可让指定从站"掉线"（不应答）或返回错误 CRC，用来验证
     超时重传 / 离线判定 / 通讯报警链路。

寄存器分区（与 mbdev.DEF 中点位定义一一对应）：
  从站1 TH-200   HR 0x0000..0x0003
  从站2 PM-300   IR 0x0000..0x000B
  从站3 TC-100   HR 0x0000..0x0002 / IR 0x0000..0x0001 / CO 0x0000..0x0001 / DI 0x0000..0x0001
  从站4 FM-400   IR 0x0000..0x0006
  从站5 IO-808   CO 0x0000..0x0003 / DI 0x0000..0x0003
]]
local modbus = require "modbus"
local mbdev = require "mbdev"

local M = {}

-- ==================== 寄存器库 ====================
local MAX_REG = 0x0100
local MAX_BIT = 0x0040

local banks = {}   -- [slave] = {hr={}, ir={}, co={}, di={}, offline=false, crc_fault=0}

local function bank(slave)
    local b = banks[slave]
    if not b then
        b = { hr = {}, ir = {}, co = {}, di = {}, offline = false, crc_fault = 0 }
        banks[slave] = b
    end
    return b
end

-- ==================== 点位读写（按 mbdev 定义换算工程量） ====================
local function set_pt(dev_id, key, eng)
    local pt = mbdev.point(key)
    if not pt then return end
    local b = bank(dev_id)
    if pt.dtype == "bool" then
        if pt.fc == 0x01 then b.co[pt.addr] = (eng ~= 0)
        elseif pt.fc == 0x02 then b.di[pt.addr] = (eng ~= 0) end
        return
    end
    local raw = math.floor((eng / pt.scale) + 0.5)
    local regs = modbus.encode(raw, pt.dtype)
    local dst = (pt.fc == 0x04) and b.ir or b.hr
    for i, r in ipairs(regs) do
        dst[pt.addr + i - 1] = r & 0xFFFF
    end
end

local function get_pt(dev_id, key)
    local pt = mbdev.point(key)
    if not pt then return 0 end
    local b = bank(dev_id)
    if pt.dtype == "bool" then
        local v = (pt.fc == 0x01) and b.co[pt.addr] or b.di[pt.addr]
        return v and 1 or 0
    end
    local src = (pt.fc == 0x04) and b.ir or b.hr
    local n = modbus.reg_count(pt.dtype)
    local regs = {}
    for i = 1, n do regs[i] = src[pt.addr + i - 1] or 0 end
    return modbus.decode(regs, pt.dtype, 1) * pt.scale
end

M.get_pt = get_pt
M.set_pt = set_pt

-- ==================== 过程模拟状态 ====================
local P = {
    tick = 0,
    th = { t = 24.0, h = 55.0 },
    pm = { ua = 380, ub = 380, uc = 380, ia = 12.5, ib = 12.2, ic = 12.8, pf = 0.95, freq = 50.0, ep = 1234.5 },
    tc = { t = -15.0, eva = -22.0, door = false, prot = false, timer = 0, manual_until = 0 },
    fm = { level = 55.0, flow = 24.0, total = 8621.0, ft = 45.0, fp = 0.45 },
    io = { estop_left = 0 },
    anomaly = nil,
}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function rnd(a)
    return (math.random() - 0.5) * (a or 1)
end

local ANOMALY_AMP = {
    temp = 13, hum = -32, ia = 11, level = 42, tcur = 14, freq = 0.9, fpres = 0.55, ftemp = 22,
}

local function anomaly_of(key)
    local a = P.anomaly
    if not a or a.key ~= key then return 0 end
    local done = a.total - a.left
    local k = done / a.total
    if k < 0 then k = 0 end
    if k > 1 then k = 1 end
    return a.amp * math.sin(k * math.pi)
end

-- ==================== 各从站过程 ====================
local function sim_th(t)
    -- 三个周期叠加：慢趋势(37) + 中周期(11) + 快波动(3.5)
    -- 快波动保证在 80 点的窗口里能看到明显的波峰波谷，而不是一条单调漂移的斜线
    local bt = 24 + math.sin(t / 37) * 1.6 + math.sin(t / 11) * 0.45
                  + math.sin(t / 3.5) * 0.35 + anomaly_of("temp")
    P.th.t = P.th.t + (bt - P.th.t) * 0.12 + rnd(0.12)
    local bh = 55 + math.sin(t / 29) * 5.5 + math.sin(t / 7) * 1.3 + anomaly_of("hum")
    P.th.h = clamp(P.th.h + (bh - P.th.h) * 0.12 + rnd(0.4), 5, 99)
    local dew = P.th.t - (100 - P.th.h) / 5
    set_pt(1, "temp", P.th.t)
    set_pt(1, "hum", P.th.h)
    set_pt(1, "dew", dew)
    local stw = 0
    if math.abs(P.th.t - 24) > 6 then stw = stw | 0x02 end
    if P.th.h > 85 or P.th.h < 15 then stw = stw | 0x04 end
    set_pt(1, "thst", stw)
end

local function sim_pm(t, dt_ms)
    local dt_h = (dt_ms or 1000) / 3600000
    P.pm.ua = clamp(P.pm.ua + ((380 + math.sin(t / 41) * 2.6 + rnd(0.6)) - P.pm.ua) * 0.15, 300, 450)
    P.pm.ub = clamp(P.pm.ub + ((380 + math.sin(t / 41 + 2.1) * 2.6 + rnd(0.6)) - P.pm.ub) * 0.15, 300, 450)
    P.pm.uc = clamp(P.pm.uc + ((380 + math.sin(t / 41 + 4.2) * 2.6 + rnd(0.6)) - P.pm.uc) * 0.15, 300, 450)
    local bi = 12.5 + math.sin(t / 23) * 1.7 + math.sin(t / 6) * 0.45 + anomaly_of("ia")
    P.pm.ia = clamp(P.pm.ia + (bi - P.pm.ia) * 0.16 + rnd(0.08), 0, 60)
    P.pm.ib = clamp(P.pm.ib + ((bi * 0.97 + rnd(0.3)) - P.pm.ib) * 0.16, 0, 60)
    P.pm.ic = clamp(P.pm.ic + ((bi * 1.03 + rnd(0.3)) - P.pm.ic) * 0.16, 0, 60)
    P.pm.pf = clamp(P.pm.pf + ((0.95 + math.sin(t / 53) * 0.03) - P.pm.pf) * 0.15, 0.5, 1.0)
    P.pm.freq = clamp(P.pm.freq + ((50 + math.sin(t / 17) * 0.07 + math.sin(t / 5) * 0.03
                  + anomaly_of("freq")) - P.pm.freq) * 0.2, 45, 55)
    local avg_i = (P.pm.ia + P.pm.ib + P.pm.ic) / 3
    local kw = 1.732 * P.pm.ua * avg_i * P.pm.pf / 1000
    P.pm.ep = P.pm.ep + kw * dt_h
    set_pt(2, "ua", P.pm.ua)
    set_pt(2, "ub", P.pm.ub)
    set_pt(2, "uc", P.pm.uc)
    set_pt(2, "ia", P.pm.ia)
    set_pt(2, "ib", P.pm.ib)
    set_pt(2, "ic", P.pm.ic)
    set_pt(2, "pw", kw)
    set_pt(2, "pf", P.pm.pf)
    set_pt(2, "freq", P.pm.freq)
    set_pt(2, "ep", P.pm.ep)
end

local function sim_tc(t, dt_ms)
    local dt_s = (dt_ms or 1000) / 1000
    local tset = get_pt(3, "tset")
    local thys = get_pt(3, "thys")
    local dly = get_pt(3, "dly")
    local b = bank(3)
    local comp = b.co[0] == true
    local defrost = b.co[1] == true

    if math.random() < 0.012 then P.tc.door = not P.tc.door end

    local manual = (os.time() < P.tc.manual_until)
    if not manual then
        if P.tc.timer > 0 then
            P.tc.timer = P.tc.timer - dt_s
        else
            local want = comp
            if P.tc.t > tset + thys / 2 then want = true end
            if P.tc.t < tset - thys / 2 then want = false end
            if want ~= comp then
                comp = want
                P.tc.timer = dly
            end
        end
        b.co[0] = comp
    end

    local target
    if defrost then
        target = 6
    elseif comp then
        target = tset - 3
    else
        target = tset + 4 + (P.tc.door and 7 or 0)
    end
    P.tc.t = P.tc.t + (target - P.tc.t) * 0.07 + rnd(0.10) + anomaly_of("tcur")
    P.tc.eva = comp and (P.tc.t - 8) or (P.tc.t - 0.5)

    set_pt(3, "tcur", P.tc.t)
    set_pt(3, "teva", P.tc.eva)
    b.di[0] = P.tc.door
    b.di[1] = P.tc.prot
end

local function sim_fm(t, dt_ms)
    local dt_s = (dt_ms or 1000) / 1000
    local io = bank(5)
    local pump = io.co[0] == true      -- DO1 进料泵
    local outv = io.co[1] == true      -- DO2 出料阀

    -- 泵/阀决定趋势，另加一项向 60% 回归的"工艺平衡"，保证液位在合理区间内摆动
    local d = -0.5
    if pump then d = d + 1.6 end
    if outv then d = d - 2.2 end
    P.fm.level = clamp(P.fm.level
        + (d * 0.8 + (60 - P.fm.level) * 0.08) * dt_s
        + rnd(0.15) + math.sin(t / 31) * 0.08, 3, 99)
    -- 上下限位开关由液位决定（而不是随机翻转），更贴近现场
    io.di[0] = (P.fm.level >= 88)
    io.di[1] = (P.fm.level <= 12)

    local bf = outv and (32 + math.sin(t / 13) * 5) or (1.5 + math.sin(t / 9) * 0.8)
    P.fm.flow = clamp(P.fm.flow + (bf - P.fm.flow) * 0.2 + rnd(0.15), 0, 80)
    P.fm.total = P.fm.total + P.fm.flow * dt_s / 3600 * 60   -- 演示加速
    P.fm.ft = clamp(P.fm.ft + ((45 + math.sin(t / 47) * 2.5 + anomaly_of("ftemp")) - P.fm.ft) * 0.1 + rnd(0.1), -10, 120)
    P.fm.fp = clamp(P.fm.fp + ((0.45 + math.sin(t / 19) * 0.05 + anomaly_of("fpres")) - P.fm.fp) * 0.15, 0, 2)

    set_pt(4, "level", P.fm.level)
    set_pt(4, "flow", P.fm.flow)
    set_pt(4, "total", P.fm.total)
    set_pt(4, "ftemp", P.fm.ft)
    set_pt(4, "fpres", P.fm.fp)
end

local function sim_io(t)
    local b = bank(5)
    -- DI1/DI2（上下限位）由 sim_fm 按液位给出，这里只管 DI3 急停与 DI4 运行反馈
    if P.io.estop_left > 0 then
        P.io.estop_left = P.io.estop_left - 1
        if P.io.estop_left <= 0 then b.di[2] = false end
    elseif math.random() < 0.004 then
        b.di[2] = true                                        -- 急停按下
        P.io.estop_left = 40
    end
    if math.random() < 0.01 then b.di[3] = not b.di[3] end   -- 运行反馈
end

-- ==================== 对外：过程推进 ====================
function M.tick(dt_ms)
    P.tick = P.tick + 1
    local t = P.tick

    if P.anomaly then
        P.anomaly.left = P.anomaly.left - 1
        if P.anomaly.left <= 0 then P.anomaly = nil end
    elseif t % 55 == 0 then
        local pool = { "temp", "hum", "ia", "level", "tcur", "freq", "fpres", "ftemp" }
        local k = pool[math.random(#pool)]
        P.anomaly = { key = k, amp = ANOMALY_AMP[k] or 5, left = 30, total = 30 }
    end

    sim_th(t)
    sim_pm(t, dt_ms)
    sim_tc(t, dt_ms)
    sim_fm(t, dt_ms)
    sim_io(t)
end

function M.inject_anomaly(key)
    key = key or "temp"
    P.anomaly = { key = key, amp = ANOMALY_AMP[key] or 5, left = 30, total = 30 }
end

-- ==================== 故障注入 ====================
function M.set_offline(slave, b)
    bank(slave).offline = b and true or false
end
function M.is_offline(slave) return bank(slave).offline == true end
function M.toggle_offline(slave)
    local b = bank(slave)
    b.offline = not b.offline
    return b.offline
end
function M.inject_crc_error(slave)
    bank(slave).crc_fault = 1
end

-- ==================== 请求处理 ====================
local function exception(fc, code)
    return string.char((fc | 0x80) & 0xFF, code & 0xFF)
end

local function do_process(slave, pdu)
    local b = bank(slave)
    local fc = string.byte(pdu, 1) or 0
    local addr = (string.byte(pdu, 2) or 0) * 256 + (string.byte(pdu, 3) or 0)
    local qty = (string.byte(pdu, 4) or 0) * 256 + (string.byte(pdu, 5) or 0)

    if fc == 0x01 or fc == 0x02 then
        local src = (fc == 0x01) and b.co or b.di
        if addr + qty > MAX_BIT or qty < 1 or qty > 0x07D0 then return exception(fc, 0x02) end
        -- 位读响应第 2 字节是"字节数" = ceil(位数/8)，不是位数本身
        local nb = math.ceil(qty / 8)
        local p = string.char(fc, nb & 0xFF)
        for i = 1, nb do
            local by = 0
            for j = 0, 7 do
                if src[addr + (i - 1) * 8 + j] == true then by = by | (1 << j) end
            end
            p = p .. string.char(by)
        end
        return p
    end

    if fc == 0x03 or fc == 0x04 then
        local src = (fc == 0x03) and b.hr or b.ir
        if addr + qty > MAX_REG or qty < 1 or qty > 0x7D then return exception(fc, 0x02) end
        local p = string.char(fc, (qty * 2) & 0xFF)
        for i = 0, qty - 1 do
            local v = src[addr + i] or 0
            p = p .. string.char((v >> 8) & 0xFF, v & 0xFF)
        end
        return p
    end

    if fc == 0x05 then
        if addr >= MAX_BIT then return exception(fc, 0x02) end
        local v = (string.byte(pdu, 4) or 0) * 256 + (string.byte(pdu, 5) or 0)
        if v ~= 0xFF00 and v ~= 0x0000 then return exception(fc, 0x03) end
        b.co[addr] = (v == 0xFF00)
        if slave == 3 then P.tc.manual_until = os.time() + 30 end
        return pdu:sub(1, 5)
    end

    if fc == 0x06 then
        if addr >= MAX_REG then return exception(fc, 0x02) end
        local v = (string.byte(pdu, 4) or 0) * 256 + (string.byte(pdu, 5) or 0)
        b.hr[addr] = v
        return pdu:sub(1, 5)
    end

    if fc == 0x0F then
        if addr + qty > MAX_BIT then return exception(fc, 0x02) end
        for i = 0, qty - 1 do
            local by = string.byte(pdu, 7 + (i // 8)) or 0
            b.co[addr + i] = ((by >> (i % 8)) & 1) == 1
        end
        if slave == 3 then P.tc.manual_until = os.time() + 30 end
        return pdu:sub(1, 5)
    end

    if fc == 0x10 then
        if addr + qty > MAX_REG then return exception(fc, 0x02) end
        for i = 0, qty - 1 do
            b.hr[addr + i] = (string.byte(pdu, 7 + i * 2) or 0) * 256 + (string.byte(pdu, 8 + i * 2) or 0)
        end
        return pdu:sub(1, 5)
    end

    return exception(fc, 0x01)
end

--[[
处理一条 RTU 请求帧

@param adu 完整 RTU 帧（含 CRC）
@return resp 完整 RTU 响应帧；不应答时返回 nil
@return reason 不应答原因（"crc" / "offline" / "noslave"）
]]
function M.handle_rtu(adu)
    local slave, pdu = modbus.rtu_unwrap(adu)
    if not slave then return nil, "crc" end
    local b = banks[slave]
    if not b then return nil, "noslave" end
    if b.offline then return nil, "offline" end

    local rpdu = do_process(slave, pdu)
    local resp = modbus.rtu_wrap(slave, rpdu)
    if b.crc_fault > 0 then
        b.crc_fault = b.crc_fault - 1
        local last = string.byte(resp, #resp)
        resp = resp:sub(1, #resp - 1) .. string.char((last ~ 0x55) & 0xFF)
    end
    return resp
end

--[[处理一条 Modbus TCP 请求（含 MBAP），返回完整响应]]
function M.handle_tcp(req)
    if (not req) or #req < 8 then return nil, "short" end
    local txn = string.byte(req, 1) * 256 + string.byte(req, 2)
    local uid = string.byte(req, 7)
    local adu = modbus.rtu_wrap(uid, req:sub(8))
    local resp, reason = M.handle_rtu(adu)
    if not resp then return nil, reason end
    local _, rpdu = modbus.rtu_unwrap(resp)
    return modbus.tcp_wrap(txn, uid, rpdu)
end

-- ==================== 初始化 ====================
function M.init()
    banks = {}
    P.tick = 0
    P.anomaly = nil
    P.tc = { t = -15.0, eva = -22.0, door = false, prot = false, timer = 0, manual_until = 0 }

    for _, dev in ipairs(mbdev.devices()) do
        local b = bank(dev.id)
        for _, pt in ipairs(dev.points) do
            -- 所有点位先按默认值落库，保证一开始读到的不是 0
            set_pt(dev.id, pt.key, pt.def or 0)
        end
        b.offline = false
        b.crc_fault = 0
    end
    -- 跑几轮让过程量进入稳态
    for i = 1, 30 do M.tick(1000) end
    log.info("mbslave", "内置虚拟从站就绪", #mbdev.devices())
end

return M
