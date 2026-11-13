--[[
@module  sim
@summary HELIOS-1 装置运行模型：放电时序、等离子体参数、磁约束、低温真空、事件
@version 1.0
@date    2026.11.12

设计原则：
1、所有量都由同一个状态机演化，参数之间保持因果：
   加热功率抬温度，温度与密度决定聚变功率，功率除以辅助加热得到 Q；
   低温或真空掉线会推高破裂风险，风险又压制电流。
2、UI 只读 M.summary()，不自己算物理量。
3、接入真实采集时，把 evolve() 里的目标值换成实测写入 M.push(key, value) 即可。
]]
local conf = require "conf"

local M = {}

local PHASES = conf.phases
local HIST = conf.sim.history

local S = {
    tick = 0,
    uptime = 0,
    clock_sec = 8 * 3600 + 42 * 60,
    paused = false,

    shot = conf.machine.shots,
    phase_i = 1,
    phase_t = 0,
    phase_name = PHASES[1].name,
    phase_key = PHASES[1].key,

    -- 等离子体
    ip = 0, bt = 0, te = 0.03, ne = 0.04, paux = 0, pfus = 0, q = 0,
    h98 = 1.00, mhd = 0.7, risk = 3, energy = 0,

    -- 低温 / 真空
    t4 = 4.35, t80 = 78.0, tcold = 12.0, tsupp = 296.0, valve_p = 4.20,
    p_vessel = 3.2e-6, p_nbi = 1.8e-5, he = conf.cryo.he_inventory,
    compressor = conf.cryo.compressor, water = 128, div_temp = 96,

    -- 可调目标
    target_ip = 1.20,
    heat_target = 15.0,
    rmp = false,
    aborted = false,

    device = {},
    events = {},
    hist = { ip = {}, paux = {}, te = {}, q = {} },
    fired = {},
}

for _, d in ipairs(conf.subsystems) do S.device[d.key] = d.on end

-- 上一次采样的最新事件（给 app 弹提示）
local last_event = nil

local function now_clock()
    local s = S.clock_sec % 86400
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

local function smooth(x)
    if x < 0 then x = 0 elseif x > 1 then x = 1 end
    return x * x * (3 - 2 * x)
end

local function jitter(amp)
    return (math.random() - 0.5) * 2 * amp
end

-- ===================== 事件 =====================
function M.log(text, level)
    local e = {
        text = text,
        level = level or "ok",
        clock = now_clock(),
        shot = S.shot,
        tick = S.tick,
    }
    table.insert(S.events, 1, e)
    while #S.events > 30 do table.remove(S.events) end
    last_event = e
    log.info("sim", "[" .. e.clock .. "] " .. text)
    return e
end

function M.events(n)
    local out = {}
    for i = 1, math.min(n or 6, #S.events) do out[i] = S.events[i] end
    return out
end

-- ===================== 时序 =====================
local function enter(i)
    S.phase_i = i
    S.phase_t = 0
    local p = PHASES[i]
    S.phase_key = p.key
    S.phase_name = p.name

    if p.key == "pump" then
        S.shot = S.shot + 1
        S.aborted = false
        M.log(string.format("第 %d 炮准备：抽真空至 3.2e-6 Pa", S.shot), "ok")
    elseif p.key == "ramp" then
        M.log(string.format("起弧成功，目标电流 %.2f MA", S.target_ip), "ok")
    elseif p.key == "heat" then
        M.log(string.format("辅助加热投入，总功率 %.1f MW", S.heat_target), "ok")
    elseif p.key == "rampdown" then
        if S.aborted then
            M.log("人工终止：执行快速电流下降", "warn")
        else
            M.log("平顶段结束，开始电流下降", "warn")
        end
    elseif p.key == "cooldown" then
        M.log(string.format("第 %d 炮结束，等离子体已关闭", S.shot), "ok")
    end
end

-- ===================== 辅助加热可用功率 =====================
local function heat_available()
    local sum = 0
    for _, h in ipairs(conf.heating) do
        if S.device[h.key] then sum = sum + h.base end
    end
    return sum
end

-- ===================== 主演化 =====================
local function evolve()
    local p = PHASES[S.phase_i]
    local pr = math.min(1, S.phase_t / math.max(1, p.dur))

    local avail = heat_available()
    local target = S.target_ip

    local ip_t, te_t, ne_t, paux_t = 0, 0.03, 0.04, 0

    if p.key == "preion" then
        ip_t, te_t, ne_t, paux_t = 0.05, 0.30, 0.10, 1.0
    elseif p.key == "ramp" then
        ip_t = target * smooth(pr)
        te_t = 0.30 + 1.50 * pr
        ne_t = 0.10 + 1.90 * pr
        paux_t = 4.5
    elseif p.key == "flat" then
        ip_t = target
        te_t = 2.20 + 0.25 * pr
        ne_t = 2.00 + 0.70 * pr
        paux_t = 8.0
    elseif p.key == "heat" then
        ip_t = target
        te_t = 2.45 + 5.95 * smooth(pr)
        ne_t = 2.70 + 1.45 * pr
        paux_t = S.heat_target
    elseif p.key == "rampdown" then
        local k = 1 - smooth(pr)
        ip_t = target * k
        te_t = 8.40 * (0.45 + 0.55 * k)
        ne_t = 4.15 * (0.40 + 0.60 * k)
        paux_t = S.heat_target * k
    end

    -- 环向场 / 极向场掉线 → 无法约束等离子体
    if not S.device.tf or not S.device.pf then
        ip_t = 0
        te_t = math.min(te_t, 0.6)
    end

    -- 辅助加热可用功率上限；加热不足则温度目标同比下调
    S.paux_target = math.min(paux_t, avail)
    if (p.key == "heat" or p.key == "rampdown") and avail > 0.1 then
        local k = 0.35 + 0.65 * math.min(1, avail / 15.0)
        te_t = te_t * k
    end

    -- 一阶惯性跟随，避免参数跳变；Ip 用限速跟随，保证波形跟得上目标曲线
    local a = 0.42
    local d_ip = ip_t - S.ip
    local step = 0.22
    if d_ip > step then d_ip = step elseif d_ip < -step then d_ip = -step end
    S.ip = S.ip + d_ip
    S.te = S.te + (te_t - S.te) * a
    S.ne = S.ne + (ne_t - S.ne) * a
    S.paux = S.paux + (S.paux_target - S.paux) * a

    if S.ip < 0.002 then S.ip = 0 end

    -- 环向场随电流建立
    S.bt = 3.50 * math.min(1, S.ip / math.max(0.1, target)) + jitter(0.004)

    -- 聚变功率：温度与密度是主因，电流提供约束
    local x = math.max(0, (S.te - 2.2) / 6.2)
    local nf = math.max(0, S.ne) / 4.15
    local if_ = math.min(1, S.ip / math.max(0.2, target))
    S.pfus = 66.0 * (x ^ 1.85) * (nf ^ 0.85) * (if_ ^ 1.10) * (1 + jitter(0.02))
    if S.pfus < 0.05 then S.pfus = 0 end
    S.q = (S.paux > 0.6) and (S.pfus / S.paux) or 0
    if S.q > 12 then S.q = 12 end

    -- 约束因子与 MHD：ELM 每 9 秒来一次锯齿
    S.h98 = 1.02 + 0.06 * math.sin(S.tick * 0.13) + jitter(0.006)
    local elm = 0
    local ph = S.tick % 9
    if (p.key == "heat" or p.key == "flat") and ph < 2 then
        elm = 2.6 * (1 - ph / 2)
    end
    S.mhd = 0.65 + elm + 0.22 * math.sin(S.tick * 0.41) + jitter(0.05)
    if S.rmp then S.mhd = S.mhd * 0.45 end

    -- 破裂风险
    local risk = 3 + 52 * ((S.ne / 4.80) ^ 6) + S.mhd * 2.6
    if not S.device.vacuum then risk = risk + 18 end
    if not S.device.cryo then risk = risk + 12 end
    if not S.device.div then risk = risk + 8 end
    if S.aborted then risk = risk + 20 end
    S.risk = math.max(1, math.min(99, risk + jitter(1.2)))

    S.energy = 18.6 * math.min(1, (S.te / 8.4)) * math.min(1, S.ne / 4.15) * (1 + jitter(0.01))

    -- 低温：压缩机负荷决定 4.5 K 回路稳定性
    local comp = S.compressor / 100
    if S.device.cryo then
        S.t4 = S.t4 + ((4.35 + (1 - comp) * 0.55 + jitter(0.008)) - S.t4) * 0.18
        S.t80 = S.t80 + ((78.0 + (1 - comp) * 6.0 + jitter(0.15)) - S.t80) * 0.15
        S.tcold = S.tcold + ((12.0 + (1 - comp) * 3.0) - S.tcold) * 0.12
        S.he = S.he - 0.05
        if S.he < 30 then
            S.he = 82
            M.log("液氦储量低于 30%，自动补液完成", "warn")
        end
    else
        S.t4 = S.t4 + (296 - S.t4) * 0.02
        S.t80 = S.t80 + (296 - S.t80) * 0.02
        S.tcold = S.tcold + (296 - S.tcold) * 0.02
    end

    -- 真空：泵组掉线时压力指数上升
    if S.device.vacuum then
        S.p_vessel = S.p_vessel + (3.2e-6 - S.p_vessel) * 0.25
        S.p_nbi = S.p_nbi + (1.8e-5 - S.p_nbi) * 0.20
    else
        S.p_vessel = S.p_vessel * 1.55
        S.p_nbi = S.p_nbi * 1.45
        if S.p_vessel > 5e-3 then S.p_vessel = 5e-3 end
    end

    -- 水冷与结构温度
    S.water = S.water + ((S.device.div and 128 or 42) - S.water) * 0.12 + jitter(0.6)
    S.div_temp = S.div_temp + ((S.pfus > 5 and 118 or 62) - S.div_temp) * 0.035 + jitter(0.3)

    -- 时钟与运行时长
    S.tick = S.tick + 1
    S.uptime = S.uptime + 1
    S.clock_sec = S.clock_sec + conf.sim.clock_step
end

-- ===================== 采样入口 =====================
function M.tick()
    last_event = nil
    if S.paused then return nil end

    local before = S.phase_i
    S.phase_t = S.phase_t + 1
    local p = PHASES[S.phase_i]
    if S.phase_t >= p.dur then
        local nxt = S.phase_i + 1
        if nxt > #PHASES then nxt = 1 end
        enter(nxt)
        if nxt == 1 then before = 0 end
    end

    evolve()

    -- 曲线历史
    local function push(arr, v)
        arr[#arr + 1] = v
        if #arr > HIST then table.remove(arr, 1) end
    end
    push(S.hist.ip, S.ip)
    push(S.hist.paux, S.paux)
    push(S.hist.te, S.te)
    push(S.hist.q, S.q)

    -- 注入事件
    for i, ev in ipairs(conf.events) do
        if not S.fired[i] and S.tick >= ev.after then
            S.fired[i] = true
            M.log(ev.text, ev.level)
            if ev.device then
                if ev.off then S.device[ev.device] = false end
                if ev.on then S.device[ev.device] = true end
            end
        end
    end

    return last_event
end

-- ===================== 对外读取 =====================
function M.summary() return S end
function M.clock() return now_clock() end
function M.phase_index() return S.phase_i end

function M.phase()
    local p = PHASES[S.phase_i]
    return {
        key = p.key,
        name = p.name,
        short = p.short,
        color = p.color,
        index = S.phase_i,
        progress = math.min(1, S.phase_t / math.max(1, p.dur)),
        t_plus = S.tick,
        total = #PHASES,
    }
end

function M.phase_at(i) return PHASES[i] end
function M.phase_count() return #PHASES end

function M.heating()
    local out = {}
    local total = 0
    for _, h in ipairs(conf.heating) do
        total = total + h.base
    end
    for _, h in ipairs(conf.heating) do
        local on = S.device[h.key]
        out[#out + 1] = {
            key = h.key, name = h.name, short = h.short,
            max = h.max, base = h.base, unit = h.unit, color = h.color,
            on = on,
            mw = on and h.base * math.min(1, S.paux / math.max(0.5, total)) or 0,
        }
    end
    return out
end

function M.device(key)
    for _, d in ipairs(conf.subsystems) do
        if d.key == key then
            return { key = key, name = d.name, note = d.note, icon = d.icon, on = S.device[key] == true }
        end
    end
    return nil
end

function M.devices() return conf.subsystems end

function M.toggle_device(key)
    S.device[key] = not S.device[key]
    local d = M.device(key)
    if d then
        M.log(d.name .. (d.on and " 已投入" or " 已退出"), d.on and "ok" or "warn")
    end
    return S.device[key]
end

function M.set_device(key, on)
    S.device[key] = on and true or false
end

function M.start_shot()
    local k = PHASES[S.phase_i].key
    if k == "pump" then return true end          -- 已在抽真空，无需重来
    if k ~= "cooldown" then return false end      -- 放电中途不允许重启
    enter(1)
    return true
end

-- 强制进入下一炮（会放弃当前炮，仅在演示时使用）
function M.next_shot()
    enter(1)
    M.log(string.format("第 %d 炮放电流程启动", S.shot), "ok")
    return true
end

function M.abort()
    if PHASES[S.phase_i].key == "pump" or PHASES[S.phase_i].key == "cooldown" then
        return false
    end
    S.aborted = true
    enter(6)   -- rampdown
    return true
end

function M.pause(v)
    S.paused = v and true or false
    M.log(S.paused and "演示模型已暂停" or "演示模型已恢复", "warn")
end

function M.is_paused() return S.paused end

function M.reset()
    S.ip, S.te, S.ne, S.paux, S.pfus, S.q = 0, 0.03, 0.04, 0, 0, 0
    S.mhd, S.risk, S.energy = 0.7, 3, 0
    S.t4, S.t80, S.tcold, S.tsupp = 4.35, 78.0, 12.0, 296.0
    S.p_vessel, S.p_nbi = 3.2e-6, 1.8e-5
    S.he = conf.cryo.he_inventory
    S.water, S.div_temp = 128, 96
    S.fired = {}
    for k in pairs(S.device) do S.device[k] = true end
    S.hist = { ip = {}, paux = {}, te = {}, q = {} }
    M.prime_history()
    enter(1)
    M.log("演示数据已重置，装置回到待机状态", "ok")
end

function M.set_target_ip(v)
    S.target_ip = math.max(0.6, math.min(2.0, v or 1.2))
end

function M.set_heat(v)
    S.heat_target = math.max(5, math.min(30, v or 15))
end

function M.set_compressor(v)
    S.compressor = math.max(50, math.min(100, v or 82))
end

function M.set_rmp(on)
    S.rmp = on and true or false
    M.log(S.rmp and "共振磁扰动（RMP）投入，抑制边缘局域模" or "RMP 已退出", S.rmp and "ok" or "warn")
end

function M.is_rmp() return S.rmp end

-- ===================== 体检项 =====================
local function health_value(d)
    local j = math.sin(S.tick * 0.21 + d.base) * d.jitter
    if d.key == "water" then
        return S.water + j
    elseif d.key == "div_temp" then
        return S.div_temp + j
    elseif d.key == "valve_p" then
        return S.valve_p + j + (S.device.cryo and 0 or 0.6)
    elseif d.key == "nbi_vac" then
        return (S.p_nbi * 1e5) + j
    elseif d.key == "tf_temp" then
        return d.base + (S.ip * 2.4) + j
    elseif d.key == "pf" then
        return d.base + j
    end
    return d.base + j
end

function M.health(key)
    for _, d in ipairs(conf.health) do
        if d.key == key then
            local v = health_value(d)
            local level = "ok"
            if (d.dhi and v >= d.dhi) or (d.dlo and v <= d.dlo) then
                level = "danger"
            elseif v > d.hi or v < d.lo then
                level = "warn"
            end
            return { def = d, value = v, level = level }
        end
    end
    return nil
end

function M.health_all()
    local out = {}
    for _, d in ipairs(conf.health) do
        out[#out + 1] = M.health(d.key)
    end
    return out
end

-- ===================== 历史预填 =====================
-- 首屏就要有波形，否则开局 60 秒是一片空白。
-- 这里造一段“上一炮”的包络，与实时数据在右端自然衔接。
function M.prime_history()
    local h = S.hist
    h.ip, h.paux, h.te, h.q = {}, {}, {}, {}
    for i = 1, HIST do
        local x = (i - 1) / (HIST - 1)
        local env
        if x < 0.14 then
            env = smooth(x / 0.14)
        elseif x < 0.66 then
            env = 1
        elseif x < 0.80 then
            env = 1 - (x - 0.66) / 0.14
        else
            env = 0
        end
        h.ip[i] = 1.18 * env
        h.paux[i] = (x > 0.30 and x < 0.80) and (10 + 5 * math.sin((x - 0.3) * 9)) or 0.4
        h.te[i] = 0.05 + 8.1 * env * env
        h.q[i] = env > 0.75 and (4.2 * (env - 0.75) / 0.25) or 0
    end
end
M.prime_history()

return M
