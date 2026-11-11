--[[
@module  room_data
@summary 华康无菌车间 - 数据引擎（五间洁净区 / 压差梯度 / 温湿度 / 粒子 / AHU / 事件流）
@version 1.0
@date    2026.11.11

=== 这个引擎在模拟什么 ===
不是随机数看板，是一条能解释的物理链：
  运行模式 -> 送风机频率 + 温湿度设定
          -> 房间压差一阶惯性跟随（门一开就往下掉，关门再爬回来）
          -> 粒子浓度跟随压差（压差失守意味着脏空气倒灌）
          -> 事件流只记状态边沿（越限、恢复、开门、切模式），不按定时刷屏

=== 接真实数据只看这一节 ===
界面只读 M.rooms[i] / M.ahu / M.state 的字段，不自己算限值：
  room.dp 对走廊压差 Pa   room.t 温度 C   room.rh 湿度 %RH
  room.p05 / room.p5 悬浮粒子 count/m3   room.grade A/C/D
  room.lim05 / lim5 该级别上限   room.door 门   room.iso 挂牌隔离
把 M.tick() 的仿真段换成"读缓存 + 算派生指标"，dashboard.lua 一行都不用改。

=== 时间与倍率 ===
demo_speed = 60：真实 1 秒 = 仿真 1 分钟，24 分钟走完一天。
曲线 96 个点每 15 分钟一个，滚动窗口，最右端永远是"现在"。
]]

local T = require "theme"

local M = {}

local NR = 5
M.NR = NR

-- 生产：双班生产，换气拉满
-- 值班：夜间无人，降换气、温度放宽，但压差不能降（GMP 24 小时要求）
-- 消毒：VHP 熏蒸，压差最高，湿度拉高，人员禁入
M.modes = {
    { key = "PROD", name = "生产", en = "PRODUCTION", dp = 18, t = 22.0, rh = 50, ach = 60, freq = 42.5 },
    { key = "IDLE", name = "值班", en = "STANDBY",    dp = 16, t = 24.0, rh = 55, ach = 30, freq = 26.0 },
    { key = "VHP",  name = "消毒", en = "VHP CYCLE",  dp = 22, t = 26.0, rh = 65, ach = 45, freq = 38.0 },
}
M.mode = 1

-- 当前选中的房间（1..5）。总览页与气候页共用同一个选择，所以它属于数据层：
-- 切页回来还是同一间，不该被页面重置。
M.sel = 2

-- 房间定义：order 压差梯度次序，tBias/rhBias 固定偏差，dpBias 相对 B 灌装间的差值
local DEF = {
    { id = "A", name = "配液间",   grade = "C", area = 38, order = 2, tBias = 0.4,  rhBias = 1.5,  dpBias = -4.0 },
    { id = "B", name = "灌装间",   grade = "A", area = 42, order = 0, tBias = -0.8, rhBias = -2.0, dpBias = 0.0  },
    { id = "C", name = "压塞间",   grade = "A", area = 26, order = 1, tBias = -0.3, rhBias = -1.0, dpBias = -2.0 },
    { id = "D", name = "更衣气闸", grade = "D", area = 16, order = 4, tBias = 1.2,  rhBias = 2.5,  dpBias = -8.0 },
    { id = "E", name = "待检包装", grade = "D", area = 54, order = 5, tBias = 1.6,  rhBias = 3.0,  dpBias = -10.0 },
}

-- 悬浮粒子限值（GMP 附录1 / ISO 14644，count/m3）
local PART = {
    A = { lim05 = 3520,    lim5 = 29,    base05 = 900,   base5 = 9,   drift = 60 },
    C = { lim05 = 352000,  lim5 = 2900,  base05 = 1200,  base5 = 12,  drift = 120 },
    D = { lim05 = 3520000, lim5 = 29000, base05 = 36000, base5 = 420, drift = 2600 },
}

M.rooms = {}
M.NPT = 96
M.sim_min = 8 * 60

local function now_hms()
    local d = os.date("*t")
    return string.format("%02d:%02d", d.hour, d.min)
end
M.now_hms = now_hms

-- ==================== 事件流 ====================
M.events = {}
M.ev_ts = 0
M.today_over = 0
local MAXEV = 24

--[[@param level 1 提示 / 2 警告 / 3 报警；key 去重键，同键 40 秒内不重复记录]]
function M.push_event(level, text, key)
    local now = (mcu and mcu.ticks and mcu.ticks()) or os.time()
    if key and M.ev_key == key and (now - (M.ev_t or 0)) < 40 then return false end
    if key then M.ev_key, M.ev_t = key, now end
    table.insert(M.events, 1, { t = now_hms(), level = level, text = text, acked = false, ts = M.ev_ts })
    M.ev_ts = M.ev_ts + 1
    while #M.events > MAXEV do table.remove(M.events) end
    if level >= 3 then M.today_over = M.today_over + 1 end
    return true
end

function M.ack_event(i)
    local e = M.events[i]
    if e and not e.acked then e.acked = true; return true end
    return false
end

function M.ack_all()
    local n = 0
    for _, e in ipairs(M.events) do
        if not e.acked then e.acked = true; n = n + 1 end
    end
    return n
end

function M.unacked()
    local n = 0
    for _, e in ipairs(M.events) do if not e.acked then n = n + 1 end end
    return n
end

-- ==================== 统计与 AHU ====================
M.state = { mode = 1, online = NR, at_grade = 2, over = 0, ok_pct = 100.0,
            ach = 60, min_dp = 18, avg_t = 22, avg_rh = 50, energy = 0 }

M.ahu = { freq = 42.5, sup_t = 19.2, flow = 8600, ret_pct = 78,
          filt = { 0.32, 0.58, 0.41 }, filt_warned = false }

-- ==================== 工具 ====================
local function rnd(a, b) return a + math.random() * (b - a) end

local function k_of(dt, tau)
    local k = 1 - math.exp(-dt / tau)
    if k < 0 then return 0 elseif k > 1 then return 1 end
    return k
end

local function push_hist(r, t, rh, dp)
    local h = r.hist
    table.remove(h.t, 1); table.remove(h.rh, 1); table.remove(h.dp, 1)
    h.t[M.NPT] = t; h.rh[M.NPT] = rh; h.dp[M.NPT] = dp
end

-- 初始历史用日周期 + 小扰动生成，首屏曲线不是一条直线
local function seed_hist(r, base, amp)
    local h = { t = {}, rh = {}, dp = {} }
    for i = 1, M.NPT do
        local ph = (i - 1) / M.NPT * math.pi * 2
        h.t[i]  = base.t + math.sin(ph - 1.2) * amp.t + rnd(-0.25, 0.25)
        h.rh[i] = base.rh + math.sin(ph + 0.6) * amp.rh + rnd(-0.8, 0.8)
        h.dp[i] = base.dp + math.sin(ph * 2 + r.order) * amp.dp + rnd(-0.5, 0.5)
    end
    r.hist = h
end

-- ==================== 初始化 ====================
function M.init()
    math.randomseed(20261111)   -- 固定种子：每次开机现象一致，方便截图与复现
    local d = os.date("*t")
    M.sim_min = d.hour * 60 + d.min
    M.events = {}
    M.ev_ts, M.today_over = 0, 0
    M.ev_key, M.ev_t = nil, nil
    M.mode = 1
    M.sel = 2

    local mo = M.modes[1]
    M.rooms = {}
    for i = 1, NR do
        local def = DEF[i]
        local p = PART[def.grade]
        local r = {
            id = def.id, name = def.name, grade = def.grade, area = def.area, order = def.order,
            tBias = def.tBias, rhBias = def.rhBias, dpBias = def.dpBias,
            lim05 = p.lim05, lim5 = p.lim5, base05 = p.base05, base5 = p.base5, drift = p.drift,
            dp = mo.dp + def.dpBias + rnd(-0.6, 0.6),
            t  = mo.t + def.tBias + rnd(-0.3, 0.3),
            rh = mo.rh + def.rhBias + rnd(-1.2, 1.2),
            p05 = p.base05 * rnd(0.85, 1.15),
            p5  = p.base5 * rnd(0.85, 1.15),
            door = false, doorT = 0, iso = false, over = false,
            last_dp_ok = true, last_p_ok = true,   -- 首帧不要刷一屏"恢复"事件
            ach = mo.ach, p05_phase = rnd(0, 6.28),
        }
        seed_hist(r, { t = mo.t + def.tBias, rh = mo.rh + def.rhBias, dp = mo.dp + def.dpBias },
                     { t = 0.55, rh = 1.6, dp = 0.7 })
        M.rooms[i] = r
    end

    M.ahu.freq, M.ahu.sup_t = mo.freq, 19.2
    M.ahu.flow, M.ahu.ret_pct = mo.ach * 150, 78
    M.ahu.filt = { 0.32, 0.58, 0.41 }
    M.ahu.filt_warned = false

    M.state = { mode = 1, online = NR, at_grade = 2, over = 0, ok_pct = 100.0,
                ach = mo.ach, min_dp = mo.dp, avg_t = mo.t, avg_rh = mo.rh, energy = 0 }

    M.push_event(1, "系统启动，五间洁净区进入监控", "boot")
    M.push_event(1, "运行模式：生产  换气 60 次/h", "mode")
end

-- ==================== 主循环 ====================
local hist_acc = 0

function M.tick(dt, speed)
    speed = speed or T.perf.demo_speed
    local mo = M.modes[M.mode]
    local k3, k8, k6 = k_of(dt, 3.0), k_of(dt, 8.0), k_of(dt, 6.0)

    M.sim_min = M.sim_min + dt * speed / 60
    hist_acc = hist_acc + dt * speed / 60
    local sample = hist_acc >= T.perf.point_min
    if sample then hist_acc = hist_acc - T.perf.point_min end

    local ok_n, over_n, dp_min, sum_t, sum_rh = 0, 0, 1e9, 0, 0

    for i = 1, NR do
        local r = M.rooms[i]

        -- 门开 8 秒自动回弹（演示用；真机接门磁就是外部写 r.door）
        if r.door then
            r.doorT = r.doorT - dt
            if r.doorT <= 0 then r.door = false end
        end

        local dp_t = mo.dp + r.dpBias - (r.door and 8.0 or 0)
        if r.iso then dp_t = 0 end
        local t_t  = mo.t + r.tBias + (r.door and 0.5 or 0)
        local rh_t = mo.rh + r.rhBias + (r.door and 3.0 or 0)

        r.dp = r.dp + (dp_t - r.dp) * k3 + rnd(-0.05, 0.05)
        r.t  = r.t  + (t_t  - r.t)  * k8 + rnd(-0.008, 0.008)
        r.rh = r.rh + (rh_t - r.rh) * k6 + rnd(-0.05, 0.05)

        -- 粒子：门开 / 压差失守时向脏空气靠，恢复后按 5 秒时间常数回落
        local pmul = 1.0
        if r.door then pmul = pmul + 1.4 end
        if r.dp < 10 then pmul = pmul + (10 - r.dp) * 0.06 end
        if r.iso then pmul = 0.7 end
        r.p05_phase = r.p05_phase + dt * 0.7
        local kp = k_of(dt, 5.0)
        r.p05 = r.p05 + ((r.base05 + math.sin(r.p05_phase) * r.drift) * pmul - r.p05) * kp
        r.p5  = r.p5  + ((r.base5 + math.sin(r.p05_phase * 0.7) * r.drift / 40) * pmul - r.p5) * kp

        r.ach = r.iso and 0 or mo.ach

        r.over = r.dp < 8 or r.t < 18 or r.t > 26 or r.rh < 45 or r.rh > 60
                 or r.p05 > r.lim05 or r.p5 > r.lim5
        if r.over then over_n = over_n + 1 else ok_n = ok_n + 1 end
        if r.dp < dp_min then dp_min = r.dp end
        sum_t, sum_rh = sum_t + r.t, sum_rh + r.rh

        if sample then push_hist(r, r.t, r.rh, r.dp) end

        -- 事件边沿：压差（文案压到 14 字内，事件卡一列放得下）
        if r.dp < 8 and r.last_dp_ok ~= false and not r.iso then
            r.last_dp_ok = false
            M.push_event(3, string.format("%s压差低 %.1fPa", r.name, r.dp), "dp" .. r.id)
        elseif r.dp >= 10 and r.last_dp_ok ~= true then
            r.last_dp_ok = true
            M.push_event(1, string.format("%s压差恢复", r.name), "dpb" .. r.id)
        end

        -- 事件边沿：粒子
        local frac = r.p05 / r.lim05
        if frac >= 1.0 and r.last_p_ok ~= false then
            r.last_p_ok = false
            M.push_event(3, string.format("%s粒子超限", r.name), "p" .. r.id)
        elseif frac < 0.85 and r.last_p_ok ~= true then
            r.last_p_ok = true
            if r.grade == "A" then
                M.push_event(1, string.format("%s粒子回落", r.name), "pb" .. r.id)
            end
        end
    end

    M.state.over, M.state.ok_pct = over_n, ok_n / NR * 100
    M.state.min_dp, M.state.avg_t, M.state.avg_rh = dp_min, sum_t / NR, sum_rh / NR
    M.state.mode, M.state.ach = M.mode, mo.ach

    -- AHU：频率跟随模式，流量跟频率，送风温度跟模式设定
    local kf = k_of(dt, 4.0)
    M.ahu.freq = M.ahu.freq + (mo.freq - M.ahu.freq) * kf + rnd(-0.02, 0.02)
    M.ahu.flow = math.floor(M.ahu.freq * 202 + rnd(-15, 15))
    M.ahu.sup_t = mo.t - 2.8 + math.sin(M.sim_min * 0.02) * 0.3
    M.ahu.ret_pct = math.floor(78 - (mo.freq - 26) * 0.35)

    -- 过滤器阻力缓慢上升：真实是几个月，演示里压到一天涨 8%
    local grow = dt * speed * 0.00004
    for i = 1, 3 do
        M.ahu.filt[i] = math.min(1, M.ahu.filt[i] + grow * (i == 3 and 0.7 or 1.0))
    end
    if M.ahu.filt[3] > 0.85 and not M.ahu.filt_warned then
        M.ahu.filt_warned = true
        M.push_event(2, string.format("高效过滤器阻力 %.0f%% 建议安排更换", M.ahu.filt[3] * 100), "filt")
    end

    -- 能耗：风机功率约 f^3，累加 kWh
    local kw = 4 + (M.ahu.freq / 50) ^ 3 * 46
    M.state.energy = M.state.energy + kw * dt * speed / 3600
end

-- ==================== 操作 ====================
--[[切模式：只改 M.mode，tick 里所有房间会一阶跟随过去，不会瞬间跳变]]
function M.set_mode(i)
    if i == M.mode then return false end
    M.mode = i
    local mo = M.modes[i]
    M.push_event(1, string.format("运行模式切换：%s  换气 %d 次/h", mo.name, mo.ach), "mode" .. i)
    return true
end

function M.next_mode()
    return M.set_mode(M.mode % #M.modes + 1)
end

--[[开门：门开 8 秒，压差掉、粒子涨，事件马上记一条。返回是否真的开了]]
function M.open_door(i)
    local r = M.rooms[i]
    if not r or r.door or r.iso then return false end
    r.door, r.doorT = true, 8
    M.push_event(1, string.format("%s 门开启", r.name), "door" .. r.id .. M.ev_ts)
    return true
end

--[[挂牌隔离 / 解除：停送风、压差归零、粒子按 0.7 倍沉降]]
function M.toggle_iso(i)
    local r = M.rooms[i]
    if not r then return nil end
    r.iso = not r.iso
    if r.iso then
        r.door = false
        M.push_event(2, string.format("%s 挂牌隔离，停止送风", r.name), "iso" .. r.id)
        return "iso"
    end
    M.push_event(1, string.format("%s 解除隔离，恢复送风", r.name), "uniso" .. r.id)
    return "uniso"
end

-- 选中房间的趋势数据（dashboard 直接读）
function M.hist_of(i)
    local r = M.rooms[i]
    return r and r.hist or nil
end

return M
