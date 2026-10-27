--[[
@module  plant_data
@summary DIGITAL TWIN - 车间模拟数据源（确定性 LCG + 平滑噪声 + 曲线缓冲）
@version 1.0
@date    2026.10.23
@author  江访

=== UI 只读字段，不关心来源 ===
真机联调时把 D.tick(dt) 换成真实采集回调（MQTT / Modbus / MES 拉取）即可，
ui 层一行都不用改——所有视图读的都是下面这几张表。

=== 为什么用固定种子 LCG ===
math.random 受平台实现影响，每次开机画面都不一样，截图比对、问题复现全都做不了。
自带 LCG（seed * 16807 % 2147483647）+ 固定种子 20261023，
同一固件每次上电序列完全一致。

=== 两条硬约定 ===
1、LCG 只在 init 里消耗。运行期会变的量一律由 simT 推
   （状态档 / 储罐 / 仪表 / 时钟），伪随机序列一旦按帧数消费，
   换个帧率画面就变了，"每次上电一模一样"就没了。
2、曲线按固定步长 SAMPLE_SEC 推格，与帧率解耦：
   跑 20fps 和 30fps 时曲线前进速度一致。
]]

local fx = require "fx"

local M = {}

-- ==================== 规模参数 ====================
local N       = 48      -- 主曲线点数
local NKPI    = 16      -- 迷你趋势点数
local NLINE   = 5       -- 产线条数
local NDEV    = 6       -- 左下设备格数
local NZONE   = 4       -- 能耗分区数
local NALARM  = 4       -- 告警行数

local SAMPLE_SEC = 0.4  -- 曲线采样步长

M.N, M.NKPI, M.NLINE, M.NDEV, M.NZONE, M.NALARM = N, NKPI, NLINE, NDEV, NZONE, NALARM

-- ==================== 数据容器 ====================
M.series = { prod = {}, power = {}, temp = {}, vib = {}, unit = {} }
M.raw    = { prod = 0, power = 0, temp = 0, vib = 0, unit = 0 }

M.kpi = {
    oee = 0,          -- 0..1
    output = 0,       -- 件
    ok = 0,           -- 良品
    yield = 0,        -- 0..1
    cycle = 0,        -- 秒
    online = 0, total = 0,
    plan = 0,         -- 计划产量
    peak = 0,         -- 峰值功率 kW
}
M.spark = {}          -- 产量迷你趋势 0..1

M.lines  = {}
M.devs   = {}
M.zones  = {}
M.alarms = {}

M.clock = { base = 8 * 3600 + 30 * 60 }   -- 08:30:00 起走

local simT = 0
local sampleT = 0
local rnd

-- ==================== 工具 ====================
local function push_series(tbl, len, v)
    for i = 1, len - 1 do tbl[i] = tbl[i + 1] end
    tbl[len] = v
end

-- 曲线配置：基线 / 幅度 / 速度（每条曲线性格不同，别用同一组参数）
local SERIES_CFG = {
    prod  = { base = 0.52, amp = 0.30, sp = 0.42 },
    power = { base = 0.55, amp = 0.24, sp = 0.31 },
    temp  = { base = 0.48, amp = 0.16, sp = 0.19 },
    vib   = { base = 0.40, amp = 0.22, sp = 0.55 },
    unit  = { base = 0.34, amp = 0.18, sp = 0.23 },   -- 单耗（与产出反相）
}

local function curve(name)
    local cf = SERIES_CFG[name]
    local v = cf.base + fx.noise1(simT * cf.sp + 7.3) * cf.amp * 2 - cf.amp
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return v
end

-- 状态档：由 simT 推，四档都能走到（不消耗 LCG）
local function state_of(freq, phase, th)
    local w = 0.5 + 0.5 * math.sin(simT * freq + phase)
    if w > th.a then return 1      -- 运行
    elseif w > th.b then return 2  -- 待机
    elseif w > th.c then return 3  -- 告警
    end
    return 4                       -- 停机
end

-- ==================== 初始化 ====================
function M.init()
    rnd = fx.rng(20261023)
    simT = 0
    sampleT = 0

    -- 曲线先铺满，避免首帧画出半截
    for name, cf in pairs(SERIES_CFG) do
        local t = M.series[name]
        for i = 1, N do
            t[i] = cf.base + (rnd() - 0.5) * cf.amp
        end
    end
    for i = 1, NKPI do
        M.spark[i] = 0.4 + rnd() * 0.4
    end

    M.kpi.output = 1180 + math.floor(rnd() * 60)
    M.kpi.plan = 1520
    M.kpi.online = 11
    M.kpi.total = 12

    -- 产线
    local names = { "SMT-A", "SMT-B", "ASM-1", "ASM-2", "PKG-1" }
    for i = 1, NLINE do
        M.lines[i] = {
            name = names[i],
            wo = string.format("WO-%d", 2610 + i),
            state = 1,
            cycle = rnd(),
            out = 180 + math.floor(rnd() * 120),
            phase = i * 0.9,
        }
    end

    -- 设备：6 格（左栏放得下 3x2）
    local tags = { "M01", "M02", "M03", "M04", "M05", "M06" }
    for i = 1, NDEV do
        M.devs[i] = {
            tag = tags[i],
            state = 1,
            load = 0.35 + rnd() * 0.6,
            health = 0.6 + rnd() * 0.38,
            phase = i * 0.7,
        }
    end

    -- 能耗分区
    local znames = { "SMT 贴装", "ASM 装配", "PKG 包装", "UTL 动力" }
    for i = 1, NZONE do
        M.zones[i] = {
            name = znames[i],
            frac = 0.3 + rnd() * 0.6,
            kwh = 0,
            phase = i * 1.1,
        }
    end

    -- 告警
    local atxt = {
        { 3, "M09 主轴超温", "SMT-A", 12 },
        { 2, "空压机压力波动", "UTL", 38 },
        { 1, "ASM-2 节拍偏低", "ASM-2", 71 },
        { 1, "冷却塔水位偏低", "UTL", 106 },
    }
    for i = 1, NALARM do
        M.alarms[i] = { level = atxt[i][1], text = atxt[i][2], src = atxt[i][3], t = atxt[i][4] }
    end

    M.tick(0)
end

-- ==================== 每帧推进 ====================
--[[
@param number dt 秒
]]
function M.tick(dt)
    simT = simT + dt

    -- ---- 曲线：按固定步长采样，与帧率解耦 ----
    sampleT = sampleT + dt
    while sampleT >= SAMPLE_SEC do
        sampleT = sampleT - SAMPLE_SEC
        for name in pairs(SERIES_CFG) do
            push_series(M.series[name], N, curve(name))
        end
        push_series(M.spark, NKPI, curve("prod"))
    end

    -- ---- 带单位读数：换算只在这一处，图元那边永远拿 0..1 ----
    local cap = M.series.prod[N]
    M.raw.prod = 240 + cap * 160                     -- 件/小时
    M.raw.power = 250 + M.series.power[N] * 220      -- kW
    M.raw.temp = 32 + M.series.temp[N] * 26          -- C
    M.raw.vib = 2.2 + M.series.vib[N] * 6.4          -- mm/s
    M.raw.unit = 0.90 + M.series.unit[N] * 1.10      -- kWh/pcs（0.90 ~ 2.00）

    -- ---- KPI ----
    M.kpi.oee = 0.83 + curve("prod") * 0.06
    M.kpi.output = M.kpi.output + dt * (2.4 + cap * 1.6)
    M.kpi.yield = 0.984 + M.series.temp[N] * 0.012
    M.kpi.cycle = 11.6 + (1 - cap) * 1.4
    M.kpi.peak = 408
    M.kpi.ok = math.floor(M.kpi.output * M.kpi.yield)

    -- ---- 产线 ----
    for i = 1, NLINE do
        local L = M.lines[i]
        L.state = state_of(0.09, L.phase, { a = 0.62, b = 0.42, c = 0.24 })
        L.cycle = (L.cycle + dt * (L.state == 1 and 0.13 or 0.02)) % 1
        if L.state == 1 then
            L.out = L.out + dt * 1.6
        end
    end

    -- ---- 设备 ----
    local nstop = 0
    for i = 1, NDEV do
        local d = M.devs[i]
        d.state = state_of(0.31, d.phase, { a = 0.55, b = 0.34, c = 0.16 })
        local target = 0.25 + fx.noise1(simT * 0.5 + i * 3.1) * 0.7
        d.load = fx.approach(d.load, target, 0.06, dt)
        local ht = 0.55 + fx.noise1(simT * 0.2 + i * 5.7) * 0.42
        d.health = fx.approach(d.health, ht, 0.04, dt)
        if d.state == 4 then nstop = nstop + 1 end
    end
    -- 在线台数与左下状态灯同源，否则'在线 11/12'和三盏红灯同时出现，一眼就假
    M.kpi.online = 12 - nstop

    -- ---- 能耗分区 ----
    for i = 1, NZONE do
        local z = M.zones[i]
        local target = 0.28 + fx.noise1(simT * 0.28 + z.phase * 2.7) * 0.66
        z.frac = fx.approach(z.frac, target, 0.05, dt)
        z.kwh = 60 + z.frac * 280
    end

    -- ---- 告警相对时间：滚动到 400 秒归零 ----
    for i = 1, NALARM do
        local a = M.alarms[i]
        a.t = a.t + dt
        if a.t > 400 then a.t = a.t - 400 end
    end

    -- ---- 时钟 ----
    M.clock.base = M.clock.base + dt
end

function M.clock_str()
    local s = math.floor(M.clock.base)
    return string.format("%02d:%02d:%02d",
        math.floor(s / 3600) % 24, math.floor(s / 60) % 60, s % 60)
end

--[[均匀采样：把 N 点曲线降到 n 点（图元预算不够时的标准做法）
@return table 长度为 n 的新数组（复用一个传入的缓冲）
]]
function M.sample(src, n, dst)
    dst = dst or {}
    local step = (N - 1) / (n - 1)
    for i = 1, n do
        local p = (i - 1) * step + 1
        local i0 = math.floor(p)
        local f = p - i0
        local a = src[i0] or 0
        local b = src[i0 + 1] or a
        dst[i] = a + (b - a) * f
    end
    return dst
end

return M
