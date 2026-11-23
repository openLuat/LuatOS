--[[
@module  sim
@summary IMM-6 工艺模型：成型周期状态机、液压与温度回路、PLC 扫描与 I/O 映像
@version 1.0
@date    2026.11.15

设计原则：
1、一切由成型周期的七个阶段驱动：阶段决定阀输出，阀输出决定压力与位置，
   压力与位置再决定锁模力、模腔压力与熔胶状态，温度回路独立跟随设定值。
2、UI 只读 M.summary() 与若干取数函数，不自己算工艺量。
3、接入真实控制器时，把 evolve() 里的目标值换成 PLC 采集写入即可，UI 层不动。
]]
local conf = require "conf"

local M = {}

local HIST = conf.sim.history
local STAGES = conf.stages

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function smooth(x)
    if x < 0 then x = 0 elseif x > 1 then x = 1 end
    return x * x * (3 - 2 * x)
end

local function jitter(a)
    return (math.random() - 0.5) * 2 * a
end

-- ===================== 状态 =====================
local S = {
    tick = 0,
    uptime = 0,
    clock_sec = 6 * 3600 + 52 * 60,
    paused = false,

    -- 周期
    stage_i = 1,
    stage_t = 0,
    cycle_time = 28.0,
    shot = 1200,
    good = 1189,
    bad = 11,
    running = true,
    need_start = false,
    fault = nil,          -- door / overtemp / robot
    fault_t = 0,

    -- 液压与位置
    clamp_kN = 0,         -- 锁模力 kN
    p_inj = 0,            -- 注射压力 bar
    p_cav = 0,            -- 模腔压力 bar
    v_inj = 0,            -- 注射速度 mm/s
    screw_mm = 90,        -- 螺杆位置 mm（90 为后退到底）
    back_p = 85,          -- 熔胶背压 bar
    mold_pct = 0,         -- 模具闭合度 0..1
    screw_pct = 1,        -- 螺杆后退度 0..1

    -- 温度
    bt = {},              -- 料筒五段实测
    mold_t = 62.0,        -- 定模温度
    mold_t2 = 57.5,       -- 动模温度
    water_t = 18.6,       -- 冷却水进水
    flow = 12.4,

    -- 设备
    oil_t = 46.2,
    servo_a = 18.4,
    cpu = 28,
    scan = 3.4,
    oee = 82.4,
    avail = 91.5,
    perf = 96.2,
    yield_pct = 99.2,
    eject_times = 2,

    -- 历史
    hist = { p_inj = {}, p_cav = {}, screw = {}, v_inj = {}, clamp = {}, cycle = {}, mold = {}, bt1 = {} },
    events = {},
    alarms = {},
    fired = {},
    start_pulse = 0,
    event_total = 0,
    actual = {},
    forced = {},
}

for i, s in ipairs(STAGES) do S.actual[i] = s.dur end

for i, z in ipairs(conf.barrel) do S.bt[i] = z.set + jitter(0.6) end

-- ===================== 事件 =====================
local function now_clock()
    local s = S.clock_sec % 86400
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

function M.log(text, level)
    local e = {
        text = text,
        level = level or "ok",
        clock = now_clock(),
        tick = S.tick,
        shot = S.shot,
    }
    table.insert(S.events, 1, e)
    S.event_total = S.event_total + 1
    while #S.events > 40 do table.remove(S.events) end
    if level == "danger" or level == "warn" then
        table.insert(S.alarms, 1, e)
        while #S.alarms > 12 do table.remove(S.alarms) end
    end
    log.info("sim", "[" .. e.clock .. "] " .. text)
    return e
end

function M.events(n)
    local out = {}
    for i = 1, math.min(n or 6, #S.events) do out[i] = S.events[i] end
    return out
end

function M.alarms(n)
    local out = {}
    for i = 1, math.min(n or 4, #S.alarms) do out[i] = S.alarms[i] end
    return out
end

function M.event_count() return S.event_total end

-- ===================== 阶段 =====================
local function stage() return STAGES[S.stage_i] end

function M.stage()
    local s = stage()
    return {
        index = S.stage_i,
        key = s.key,
        name = s.name,
        short = s.short,
        color = s.color,
        dur = s.dur,
        elapsed = S.stage_t,
        progress = math.min(1, S.stage_t / math.max(0.01, s.dur)),
        total = #STAGES,
    }
end

function M.stage_at(i) return STAGES[i] end
function M.stage_count() return #STAGES end

-- 各段设定时长与上一轮实测时长
function M.stage_times()
    local out = {}
    for i, s in ipairs(STAGES) do
        local a = S.actual[i] or s.dur
        out[i] = { def = s, set = s.dur, actual = a, dev = a - s.dur }
    end
    return out
end

local function enter(i)
    S.stage_i = i
    S.stage_t = 0
    local s = STAGES[i]
    if s.key == "close" then
        S.shot = S.shot + 1
        S.start_pulse = 2
        M.log(string.format("第 %d 模开始，合模", S.shot), "ok")
    elseif s.key == "inject" then
        S.v_inj = 52
    elseif s.key == "takeout" then
        -- 一炮结束
    end
end

-- ===================== 故障 =====================
local function set_fault(key)
    S.fault = key
    S.fault_t = 0
    S.running = false
    S.p_inj, S.p_cav, S.v_inj, S.clamp_kN = 0, 0, 0, 0
end

local function clear_fault()
    S.fault = nil
    S.fault_t = 0
    S.need_start = true
end

-- ===================== 主演化 =====================
local function evolve()
    local st = stage()
    local pr = math.min(1, S.stage_t / math.max(0.01, st.dur))

    -- 目标值：由阶段与阀输出决定
    local clamp_t, pinj_t, pcav_t, v_t = 0, 0, 0, 0
    local mold_t, screw_t = 0, 1

    if not S.running then
        clamp_t, pinj_t, pcav_t, v_t = 0, 0, 0, 0
        mold_t = S.mold_pct
        screw_t = S.screw_pct
    else
        if st.key == "close" then
            clamp_t = conf.machine.clamp * smooth(pr)
            mold_t = 1
            screw_t = 1
        elseif st.key == "inject" then
            clamp_t = conf.machine.clamp
            mold_t = 1
            v_t = 52
            pinj_t = 1450 * smooth(math.min(1, pr / 0.30)) * (1 - 0.05 * pr)
            pcav_t = pinj_t * 0.55
            screw_t = 1 - 0.92 * smooth(pr)
        elseif st.key == "hold" then
            clamp_t = conf.machine.clamp
            mold_t = 1
            pinj_t = 620 * (0.96 + 0.04 * math.sin(S.tick * 0.7))
            pcav_t = 560 - 180 * pr
            screw_t = 0.08
        elseif st.key == "cool" then
            clamp_t = conf.machine.clamp
            mold_t = 1
            pinj_t = 0
            pcav_t = math.max(0, 380 * (1 - pr / 0.35))
            screw_t = 0.08 + 0.92 * smooth(pr)
            v_t = 0
        elseif st.key == "open" then
            clamp_t = conf.machine.clamp * (1 - smooth(pr))
            mold_t = 0
            screw_t = 1
        elseif st.key == "eject" then
            clamp_t = 0
            mold_t = 0
            screw_t = 1
        else
            clamp_t = 0
            mold_t = 0
            screw_t = 1
        end
    end

    -- 一阶跟随：液压系统响应比采样快，系数取大一点
    local a = 0.45
    S.clamp_kN = S.clamp_kN + (clamp_t - S.clamp_kN) * a + jitter(4)
    S.p_inj = S.p_inj + (pinj_t - S.p_inj) * 0.55 + jitter(2)
    S.p_cav = S.p_cav + (pcav_t - S.p_cav) * 0.38 + jitter(3)
    S.v_inj = S.v_inj + (v_t - S.v_inj) * 0.5
    S.mold_pct = S.mold_pct + (mold_t - S.mold_pct) * 0.42
    S.screw_pct = S.screw_pct + (screw_t - S.screw_pct) * 0.40

    if S.clamp_kN < 0 then S.clamp_kN = 0 end
    if S.p_inj < 0 then S.p_inj = 0 end
    if S.p_cav < 0 then S.p_cav = 0 end

    S.screw_mm = 8 + 82 * S.screw_pct

    -- 熔胶背压：冷却段螺杆旋转时建立
    local back_t = (S.running and (st.key == "cool" or st.key == "takeout")) and 85 or 12
    S.back_p = S.back_p + (back_t - S.back_p) * 0.20 + jitter(0.6)

    -- 料筒温度：PI 回路简化为指数跟随，超温故障时二段抬升
    for i, z in ipairs(conf.barrel) do
        local target = z.set
        if S.fault == "overtemp" and i == 2 then target = z.set + 14 end
        if S.fault == "overtemp" and i == 2 then
            S.bt[i] = S.bt[i] + (target - S.bt[i]) * 0.22 + jitter(0.08)
        else
            S.bt[i] = S.bt[i] + (target + jitter(0.5) - S.bt[i]) * 0.18
        end
    end

    -- 模具温度：注射与保压段被熔料加热，冷却段回落
    local mold_target = 62.0
    if S.running and (st.key == "inject" or st.key == "hold") then mold_target = 64.2 end
    if S.running and st.key == "cool" then mold_target = 60.4 end
    S.mold_t = S.mold_t + (mold_target - S.mold_t) * 0.10 + jitter(0.05)
    S.mold_t2 = S.mold_t2 + ((mold_target - 4.2) - S.mold_t2) * 0.10 + jitter(0.05)

    -- 冷却水
    S.flow = S.flow + ((S.fault and 9.4 or 12.4) - S.flow) * 0.12 + jitter(0.05)
    S.water_t = S.water_t + ((18.4 + 1.6 * math.min(1, S.mold_t / 64)) - S.water_t) * 0.08

    -- 设备负荷
    local load = (S.running and (st.key == "inject" or st.key == "hold")) and 1 or 0.45
    S.servo_a = S.servo_a + ((12 + 14 * load) - S.servo_a) * 0.15 + jitter(0.3)
    S.oil_t = S.oil_t + ((44 + 4 * load) - S.oil_t) * 0.05 + jitter(0.05)

    -- PLC 扫描
    S.cpu = clamp(S.cpu + jitter(1.6) + (S.cpu < 26 and 0.6 or (S.cpu > 42 and -0.6 or 0)), 18, 48)
    S.scan = clamp(S.scan + jitter(0.12) + (3.4 - S.scan) * 0.2, 2.4, 5.6)

    -- 综合效率
    local avail_t = S.fault and 62 or 91.5
    S.avail = S.avail + (avail_t - S.avail) * 0.05
    S.perf = 96.2 + jitter(0.2)
    S.yield_pct = clamp(S.yield_pct + jitter(0.06), 97.6, 99.8)
    S.oee = S.avail * S.perf * S.yield_pct / 10000

    -- 时钟与计数
    S.tick = S.tick + 1
    S.uptime = S.uptime + 1
    S.clock_sec = S.clock_sec + conf.sim.clock_step
    if S.start_pulse > 0 then S.start_pulse = S.start_pulse - 1 end
end

-- ===================== 采样入口 =====================
function M.tick()
    if S.paused then return nil end

    -- 场景脚本
    for i, sc in ipairs(conf.scenario) do
        if not S.fired[i] and S.tick >= sc.after then
            S.fired[i] = true
            if sc.kind == "fault" then
                set_fault(sc.fault)
                M.log(sc.text, sc.level or "danger")
            elseif sc.kind == "clear" then
                clear_fault()
                M.log(sc.text, "ok")
            elseif sc.kind == "note" then
                M.log(sc.text, "warn")
            end
        end
    end

    if S.fault then S.fault_t = S.fault_t + 1 end

    -- 复位后等操作员按启动
    if S.need_start and not S.fault and S.fault_t == 0 then
        -- 复位完成计 6 拍后自动启动，模拟操作员按启动按钮
        S.wait_start = (S.wait_start or 0) + 1
        if S.wait_start >= 6 then
            S.wait_start = 0
            S.need_start = false
            S.running = true
            M.log("启动按钮按下，循环恢复", "ok")
        end
    end

    -- 阶段推进：停机时计时冻结
    if S.running then
        S.stage_t = S.stage_t + conf.sim.clock_step
        local st = stage()
        if S.stage_t >= st.dur then
            -- 记录本段实测时长，供工艺页做设定/实测对照
            S.actual[S.stage_i] = st.dur * (1 + jitter(0.035))
            local nxt = S.stage_i + 1
            if nxt > #STAGES then nxt = 1 end
            enter(nxt)
        end
    end

    evolve()

    -- 历史缓冲
    local function push(arr, v)
        arr[#arr + 1] = v
        if #arr > HIST then table.remove(arr, 1) end
    end
    push(S.hist.p_inj, S.p_inj)
    push(S.hist.p_cav, S.p_cav)
    push(S.hist.screw, S.screw_mm)
    push(S.hist.v_inj, S.v_inj)
    push(S.hist.clamp, S.clamp_kN)
    push(S.hist.cycle, S.cycle_time)
    push(S.hist.mold, S.mold_t)
    push(S.hist.bt1, S.bt[1] or 0)

    return S.events[1]
end

-- ===================== 对外读取 =====================
function M.summary() return S end
function M.clock() return now_clock() end

function M.is_running() return S.running end

-- 运行/待机/报警三态
function M.mode()
    if S.fault then return "fault", "故障停机" end
    if not S.running then return "idle", "待机" end
    return "run", "运行"
end

-- ===================== 温度与偏差 =====================
function M.zone(i)
    local z = conf.barrel[i]
    if not z then return nil end
    local v = S.bt[i] or z.set
    local d = v - z.set
    local level = "ok"
    if S.fault == "overtemp" and i == 2 then level = "danger"
    elseif v > z.hi or v < z.lo then level = "warn" end
    if v >= z.dhi then level = "danger" end
    return { def = z, value = v, dev = d, level = level, pct = clamp((v - 180) / 80, 0, 1) }
end

function M.zones()
    local out = {}
    for i = 1, #conf.barrel do out[i] = M.zone(i) end
    return out
end

-- 料温到达：五段全部进入带宽
function M.temp_ready()
    for i, z in ipairs(conf.barrel) do
        local v = S.bt[i] or 0
        if v < z.lo or v > z.hi then return false end
    end
    return true
end

-- ===================== I/O 映像 =====================
--[[
DI / DO 由周期与故障派生，不是随机翻转：
模具闭合到位看 mold_pct，机械手原点看 fault，料温到达看五段带宽。
]]
function M.di_bits()
    local st = stage()
    local run = S.running
    return {
        [1] = S.start_pulse > 0,                       -- I0.0 启动按钮（脉冲）
        [2] = false,                                   -- I0.1 停止按钮
        [3] = S.fault ~= "door",                       -- I0.2 安全门闭合
        [4] = S.mold_pct > 0.96,                       -- I0.3 模具闭合到位
        [5] = S.fault ~= "robot",                      -- I0.4 机械手原点
        [6] = M.temp_ready(),                          -- I0.5 料温到达
        [7] = S.mold_pct < 0.04,                       -- I0.6 开模到位
        [8] = S.fault ~= "door",                       -- I0.7 急停回路
        [9] = run and (st.key == "eject" or st.key == "takeout"),
        [10] = true,                                   -- I1.1 料斗料位
        [11] = true,                                   -- I1.2 模温机运行
        [12] = S.flow > 9.5,                           -- I1.3 冷却水流量
        [13] = true,                                   -- I1.4 液压油位
        [14] = true,                                   -- I1.5 润滑压力
        [15] = true,                                   -- I1.6 安全光幕
        [16] = S.fault ~= "door",                      -- I1.7 门锁反馈
    }
end

function M.do_bits()
    local st = stage()
    local run = S.running
    local function on(key) return run and st.key == key end
    return {
        [1] = on("close"),                             -- Q0.0 合模阀
        [2] = on("inject"),                            -- Q0.1 注射阀
        [3] = on("hold"),                              -- Q0.2 保压阀
        [4] = on("open"),                              -- Q0.3 开模阀
        [5] = on("eject"),                             -- Q0.4 顶针阀
        [6] = on("cool"),                              -- Q0.5 熔胶马达
        [7] = on("takeout"),                           -- Q0.6 机械手取件
        [8] = S.fault ~= nil,                          -- Q0.7 故障指示
        [9] = S.fault ~= nil,                          -- Q1.0 报警蜂鸣
        [10] = true,                                   -- Q1.1 模温机加热
        [11] = true,                                   -- Q1.2 冷却水阀
        [12] = true,                                   -- Q1.3 料斗干燥
        [13] = on("eject") or on("takeout"),           -- Q1.4 输送带
        [14] = run and not S.fault,                    -- Q1.5 三色灯绿
        [15] = S.fault ~= nil,                         -- Q1.6 三色灯黄
        [16] = S.fault ~= nil,                         -- Q1.7 三色灯红
    }
end

function M.ai_values()
    local vals = { S.p_inj, S.p_cav, S.clamp_kN, S.screw_mm, S.back_p,
                   S.bt[1] or 0, S.mold_t, S.water_t }
    local out = {}
    for i, d in ipairs(conf.ai) do
        local v = vals[i] or 0
        out[i] = { def = d, value = v, pct = clamp(v / d.max * 100, 0, 100) }
    end
    return out
end

function M.ao_values()
    local st = stage()
    -- 工程量本身，不是百分比：bar / ℃ / %
    local vals = {
        (S.running and st.key == "inject") and 78 or 0,   -- AO0 比例阀给定 %
        S.back_p,                                          -- AO1 背压给定 bar
        62.0,                                              -- AO2 模温给定 ℃
        (st.key == "eject") and 60 or 0,                   -- AO3 顶出速度 %
    }
    local out = {}
    for i, d in ipairs(conf.ao) do
        local v = vals[i] or 0
        out[i] = { def = d, value = v, pct = clamp(v / d.max * 100, 0, 100) }
    end
    return out
end

-- ===================== 梯形图位状态 =====================
function M.bits()
    local st = stage()
    local prog = math.min(1, S.stage_t / math.max(0.01, st.dur))
    local di, dob = M.di_bits(), M.do_bits()
    local map = {
        ["I0.0"] = di[1], ["I0.1"] = di[2], ["I0.2"] = di[3], ["I0.3"] = di[4],
        ["I0.4"] = di[5], ["I0.5"] = di[6], ["I0.6"] = di[7], ["I0.7"] = di[8],
        ["I1.0"] = di[9], ["I1.6"] = di[15],
        ["Q0.0"] = dob[1], ["Q0.1"] = dob[2], ["Q0.2"] = dob[3], ["Q0.3"] = dob[4],
        ["Q0.4"] = dob[5], ["Q0.5"] = dob[6], ["Q0.6"] = dob[7], ["Q0.7"] = dob[8],
        ["M0.0"] = S.running,
        ["M0.1"] = S.running and (S.fault == nil) and (S.mold_pct > 0.9),
        ["M0.2"] = st.key == "inject",
        ["M0.3"] = st.key == "hold",
        ["M0.4"] = st.key == "open",
        ["M0.5"] = S.fault ~= nil,
        ["M0.6"] = di[8] and di[3] and di[15],
        ["T1"] = (st.key == "inject" and prog > 0.18) or st.key == "hold",
        ["T2"] = (st.key == "open" or st.key == "eject" or st.key == "takeout"),
    }
    -- 强制值覆盖实时值，与真实 PLC 的“强制表优先”一致
    for tag in pairs(S.forced) do map[tag] = true end
    return map
end

-- ===================== 强制表 =====================
function M.force(tag, on)
    if on then
        S.forced[tag] = true
        M.log("强制 " .. tag .. " = ON", "warn")
    else
        S.forced[tag] = nil
        M.log("取消强制 " .. tag, "ok")
    end
    return S.forced[tag] == true
end

function M.is_forced(tag) return S.forced[tag] == true end

function M.force_list()
    local out = {}
    for tag in pairs(S.forced) do out[#out + 1] = tag end
    table.sort(out)
    return out
end

function M.clear_force()
    local n = 0
    for _ in pairs(S.forced) do n = n + 1 end
    S.forced = {}
    if n > 0 then M.log(string.format("已取消 %d 个强制点", n), "ok") end
    return n
end

-- ===================== 体检 =====================
local function health_value(d)
    local j = math.sin(S.tick * 0.17 + d.base) * d.jitter
    if d.key == "water" then return S.flow + j end
    if d.key == "oil" then return S.oil_t + j end
    if d.key == "servo" then return S.servo_a + j end
    if d.key == "clean" then return d.base + (S.fault and 0.4 or 0) + j end
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
    for _, d in ipairs(conf.health) do out[#out + 1] = M.health(d.key) end
    return out
end

-- ===================== 控制 =====================
function M.start()
    if S.fault then return false, "故障未复位" end
    S.running = true
    S.need_start = false
    S.start_pulse = 2
    M.log("启动按钮按下，循环开始", "ok")
    return true
end

function M.stop()
    S.running = false
    M.log("停止按钮按下，循环在阶段末停止", "warn")
    return true
end

function M.pause(v)
    S.paused = v and true or false
    M.log(S.paused and "演示模型已暂停" or "演示模型已恢复", "warn")
end

function M.is_paused() return S.paused end

function M.reset_fault()
    if not S.fault then return false end
    M.log("操作员复位故障：" .. tostring(S.fault), "ok")
    clear_fault()
    return true
end

function M.reset()
    S.shot = 1200
    S.good, S.bad = 1189, 11
    S.stage_i, S.stage_t = 1, 0
    S.running = true
    S.fault = nil
    S.need_start = false
    S.p_inj, S.p_cav, S.v_inj, S.clamp_kN = 0, 0, 0, 0
    S.mold_pct, S.screw_pct = 0, 1
    S.fired = {}
    S.alarms = {}
    S.hist = { p_inj = {}, p_cav = {}, screw = {}, v_inj = {}, clamp = {}, cycle = {}, mold = {}, bt1 = {} }
    for i, z in ipairs(conf.barrel) do S.bt[i] = z.set end
    M.log("演示数据已重置，单元回到初始状态", "ok")
end

-- ===================== 历史预填 =====================
--[[
首屏就要有波形。这里按一个标准周期造两条曲线：
前 21 秒注射/保压/冷却的压力包络 + 螺杆位置回退，与实时数据在右端衔接。
]]
function M.prime_history()
    local h = S.hist
    for i = 1, HIST do
        local phase = (i - 1) / HIST * 2.4        -- 2.4 个周期
        local p = phase % 1
        local pinj, pcav, screw, v
        if p < 0.09 then
            pinj, pcav, v = 1450 * (p / 0.09), 900 * (p / 0.09), 52
            screw = 90 - 78 * smooth(p / 0.09)
        elseif p < 0.30 then
            pinj, pcav, v = 620, 900 - 380 * ((p - 0.09) / 0.21), 0
            screw = 12
        elseif p < 0.66 then
            pinj, pcav, v = 0, math.max(0, 520 * (1 - (p - 0.30) / 0.12)), 0
            screw = 12 + 78 * smooth((p - 0.30) / 0.36)
        else
            pinj, pcav, v = 0, 0, 0
            screw = 90
        end
        h.p_inj[i] = pinj
        h.p_cav[i] = pcav
        h.screw[i] = screw
        h.v_inj[i] = v
        h.clamp[i] = (p < 0.66) and 1800 or math.max(0, 1800 * (1 - (p - 0.66) / 0.12))
        h.cycle[i] = 28.0 + math.sin(i * 0.3) * 0.25
        h.mold[i] = 62 + math.sin(i * 0.2) * 0.8
        h.bt1[i] = 240 + math.sin(i * 0.4) * 0.4
    end
end
M.prime_history()

-- 上电自检：让事件流在首屏就有内容，而不是空表
M.log("PLC 上电自检完成，液压与温控就绪，单元待机", "ok")

return M
