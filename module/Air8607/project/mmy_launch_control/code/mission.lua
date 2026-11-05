--[[
@module  mission
@summary 任务时序引擎：自检 → 终端倒计时 → 上升段 → 入轨，含遥测插值与事件派发
@version 1.0
@date    2026.11.04

设计要点：
1、所有界面只读 st 里的数字，不自己算时间，保证"倒计时/曲线/事件流"永远同源；
2、事件一次只触发一次（fired 标记），UI 订阅后做一次性动效与播报；
3、飞行段时间压缩 mission.flight_speed 倍，260 秒任务约 43 秒放完，
   倒计时段仍按 1 秒 1 秒走，让人能跟上"十、九、八……"；
4、无操作时自动演示（展厅模式），手动点按钮会从头接管。
]]
local conf = require "conf"
local kit = require "kit"

local M = {}

local cfg = conf.mission

local st = {
    phase      = "standby",   -- standby / check / countdown / ascent / orbit / abort
    mt         = cfg.standby_t,  -- 任务时间（秒），起飞前为负
    dwell      = 0,           -- 当前阶段已停留的实时秒数
    checks     = 0,           -- 已完成自检项
    alt        = 0,           -- 高度 km
    vel        = 0,           -- 速度 m/s
    acc        = 0,           -- 过载 g
    thrust     = 0,           -- 推力 %
    tilt       = 0,           -- 重力转弯角（度）
    ignite     = 0,           -- 点火强度 0..1
    stage2     = false,       -- 二级是否在工作
    sep        = false,       -- 一级已分离
    fairing    = false,       -- 整流罩已抛
    fuel       = { lox = 100, rp1 = 100, s2 = 100, power = 100 },
    events     = {},          -- 时序表副本（带 state / fired）
    active     = 1,           -- 当前进行到的事件下标
    rev        = 0,           -- 结构性变化计数（UI 用来判断是否重绘时序卡）
    auto       = false,       -- 自动演示（默认关闭，点"开始倒计时"手动发射）
    aborted_at = 0,
}
M.st = st

local subs = {}

-- 只念"里程碑"，起飞/入轨/中止由阶段切换负责，避免一句话说两遍
local VOICE_KEYS = {
    ignition = "主发动机点火",
    maxq     = "通过最大动压",
    sep1     = "一级分离，二级点火",
    fairing  = "整流罩分离",
    seco     = "二级关机",
}

-- ==================== 订阅 ====================
--- 订阅任务事件
-- @param function fn fn(msg)  msg.type = phase / event / say / checks
function M.subscribe(fn)
    subs[#subs + 1] = fn
end

local function emit(msg)
    for i = 1, #subs do
        local ok, err = pcall(subs[i], msg)
        if not ok then log.error("mission", "订阅回调异常", tostring(err)) end
    end
end

-- ==================== 初始化时序表 ====================
local function build_events()
    st.events = {}
    for i = 1, #conf.events do
        local e = conf.events[i]
        st.events[i] = {
            t = e.t, name = e.name, key = e.key,
            state = "todo", fired = false,
        }
    end
end
build_events()

-- ==================== 遥测插值 ====================
--- 任意任务时刻的高度/速度（曲线卡画"计划弹道"也用它）
-- @param number t 任务时间秒
-- @return number alt_km, number vel_ms
function M.telemetry_at(t)
    local k = conf.telemetry
    if t <= k[1][1] then return 0, 0 end
    local last = k[#k]
    if t >= last[1] then return last[2], last[3] end
    for i = 2, #k do
        local a, b = k[i - 1], k[i]
        if t <= b[1] then
            local p = kit.smooth((t - a[1]) / (b[1] - a[1]))
            return kit.lerp(a[2], b[2], p), kit.lerp(a[3], b[3], p)
        end
    end
    return last[2], last[3]
end

local function update_telemetry()
    local t = st.mt
    if t <= 0 then
        st.alt, st.vel, st.acc = 0, 0, 0
    else
        st.alt, st.vel = M.telemetry_at(t)
        local v0 = M.telemetry_at(t - 1)
        st.acc = kit.clamp((st.vel - v0) / 9.8, 0, 4.6)
    end

    -- 推力曲线：起飞前 3 秒渐推到 100%，max-Q 段收油门，一级分离后换二级
    local thr = 0
    if st.phase == "countdown" and t >= -3 then
        thr = kit.clamp((t + 3) / 3, 0, 1) * 100
    elseif st.phase == "ascent" or st.phase == "orbit" then
        if t >= 150 then
            thr = 92
        elseif t >= 55 and t < 72 then
            thr = 72
        else
            thr = 100
        end
    elseif st.phase == "abort" then
        thr = math.max(0, st.thrust - 60)
    end
    st.thrust = thr

    -- 点火强度：用于火焰长度；中止后快速熄灭
    if st.phase == "countdown" then
        st.ignite = kit.clamp((t + 3) / 3, 0, 1) * 0.75
    elseif st.phase == "ascent" then
        st.ignite = 1
    elseif st.phase == "orbit" then
        st.ignite = 0
    elseif st.phase == "abort" then
        st.ignite = math.max(0, st.ignite - 0.06)
    else
        st.ignite = 0
    end

    -- 重力转弯：12 秒起程序转弯，90 秒转到 22 度
    if t > 12 then
        st.tilt = 22 * kit.smooth((t - 12) / 78)
    else
        st.tilt = 0
    end

    -- 推进剂余量
    local lox = 100
    if t > 0 then lox = kit.lerp(100, 8, kit.clamp(t / 150, 0, 1)) end
    st.fuel.lox = lox
    st.fuel.rp1 = lox
    if t >= 150 then
        st.fuel.s2 = kit.lerp(100, 10, kit.clamp((t - 150) / 110, 0, 1))
    else
        st.fuel.s2 = 100
    end
    st.fuel.power = kit.lerp(100, 94, kit.clamp(st.dwell / 120 + (t > 0 and t / 400 or 0), 0, 1))

    st.sep = t >= 150
    st.stage2 = t >= 152
    st.fairing = t >= 175
end

-- ==================== 事件推进 ====================
local function refresh_event_state()
    local changed = false
    for i = 1, #st.events do
        local e = st.events[i]
        local done = (st.mt >= e.t + 0.001) or (st.phase == "orbit")
        local s = done and "done" or "todo"
        if s ~= e.state then
            e.state = s
            changed = true
        end
    end
    -- active 取第一个未完成项（全部完成时停在最后一项）
    local active = #st.events
    for i = 1, #st.events do
        if st.events[i].state == "todo" then active = i break end
    end
    if active ~= st.active then
        st.active = active
        changed = true
    end
    if changed then st.rev = st.rev + 1 end

    -- 新事件触发
    for i = 1, #st.events do
        local e = st.events[i]
        if not e.fired and st.mt >= e.t then
            e.fired = true
            emit({ type = "event", ev = e, index = i })
            local say = VOICE_KEYS[e.key]
            if say then emit({ type = "say", text = say }) end
        end
    end
end

-- ==================== 阶段切换 ====================
local function set_phase(p)
    st.phase = p
    st.dwell = 0
    st.rev = st.rev + 1
    emit({ type = "phase", phase = p })
end

function M.reset(silent)
    st.mt = cfg.standby_t
    st.checks = 0
    st.alt, st.vel, st.acc = 0, 0, 0
    st.thrust = 0
    st.ignite = 0
    st.tilt = 0
    st.sep, st.stage2, st.fairing = false, false, false
    st.fuel = { lox = 100, rp1 = 100, s2 = 100, power = 100 }
    build_events()
    st.active = 1
    st.aborted_at = 0
    if silent then
        st.phase = "standby"
        st.dwell = 0
        st.rev = st.rev + 1
    else
        set_phase("standby")
    end
end

function M.start()
    if st.phase ~= "standby" and st.phase ~= "orbit" and st.phase ~= "abort" then
        return false, "当前阶段不能启动"
    end
    M.reset(true)
    st.checks = 0
    set_phase("check")
    emit({ type = "say", text = "开始发射前自检" })
    emit({ type = "checks", done = 0, total = #conf.checks })
    return true
end

function M.abort()
    if st.phase == "standby" or st.phase == "orbit" or st.phase == "abort" then
        return false, "当前阶段无需中止"
    end
    st.aborted_at = st.dwell
    set_phase("abort")
    emit({ type = "say", text = "任务中止，发动机已关机" })
    return true
end

function M.set_auto(on)
    st.auto = on and true or false
    return st.auto
end

-- ==================== 主循环 ====================
local function step_check(dt)
    local gap = cfg.check_gap
    local finished = math.floor(st.dwell / gap)
    if finished > #conf.checks then finished = #conf.checks end
    if finished ~= st.checks then
        st.checks = finished
        st.rev = st.rev + 1
        emit({ type = "checks", done = st.checks, total = #conf.checks })
    end
    if st.dwell >= #conf.checks * gap + cfg.check_hold then
        st.mt = cfg.count_from
        st.dwell = 0
        set_phase("countdown")
    end
end

function M.tick(dt)
    st.dwell = st.dwell + dt

    if st.phase == "standby" then
        st.mt = cfg.standby_t
        update_telemetry()
        if st.auto and st.dwell >= cfg.auto_idle then M.start() end

    elseif st.phase == "check" then
        step_check(dt)

    elseif st.phase == "countdown" then
        st.mt = st.mt + dt
        if st.mt >= 0 then
            st.mt = 0
            update_telemetry()
            set_phase("ascent")
            emit({ type = "say", text = "起飞" })
        else
            update_telemetry()
        end

    elseif st.phase == "ascent" then
        st.mt = st.mt + dt * cfg.flight_speed
        if st.mt >= cfg.orbit_t then
            st.mt = cfg.orbit_t
            update_telemetry()
            set_phase("orbit")
            emit({ type = "say", text = "载荷入轨，任务成功" })
        else
            update_telemetry()
        end

    elseif st.phase == "orbit" then
        st.mt = cfg.orbit_t
        update_telemetry()
        if st.auto and st.dwell >= cfg.auto_after then M.reset() return end

    elseif st.phase == "abort" then
        update_telemetry()
        if st.auto and st.dwell >= cfg.auto_after then M.reset() return end
    end

    refresh_event_state()
end

--- 阶段文案与配色键（UI 直接取用，避免各处重复写"上升段"字符串）
function M.phase_info()
    local p = st.phase
    if p == "standby" then return "待命", "ink2" end
    if p == "check" then return "系统自检", "cyan" end
    if p == "countdown" then return "倒计时", "amber" end
    if p == "ascent" then return "上升段", "amber" end
    if p == "orbit" then return "已入轨", "green" end
    return "任务中止", "red"
end

--- 倒计时显示值（含待命读数）
function M.clock()
    if st.phase == "standby" then return cfg.standby_t end
    if st.phase == "check" then return cfg.count_from end
    return st.mt
end

function M.check_total() return #conf.checks end
function M.check_name(i) return conf.checks[i] end

return M
