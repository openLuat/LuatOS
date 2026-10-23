--[[
@module  board_data
@summary INDUS BOARD - 工业产线模拟数据源（产线 / 设备 / 质量 / 能耗）
@version 1.0
@date    2026.10.23
@author  江访

=== 这一层解决什么 ===
看板上的部件要"在动"才看得出效果，但数据本身不是本工程的重点。
所以把所有假数据收在一个文件里：UI 只读字段、不关心来源，
真机联调时把 D.tick 换成真实采集回调即可，绘图代码一行不用改。

=== 为什么用自带 LCG 而不是 math.random ===
math.random 的种子受平台实现影响，每次开机画面都不一样，
截图/比对/复现问题全都做不到。这里用固定种子的 LCG，
每次上电生成的序列完全一致。

=== 值域约定 ===
所有"给图元画的"量都是 0..1 归一化值（D.series / D.lines.cycle / D.dev.load / D.pareto），
所有"给 label 显示的"量都是带单位的真实值（D.kpi / D.raw）。
这样绘图代码里不需要再做量程换算，单位换算只发生在这里一处。

=== 采样节拍 ===
曲线以 SAMPLE_SEC 固定步长推进，与 UI 帧率解耦：
跑 20fps 和 30fps 时曲线推进速度一致。
]]

local M = {}

-- ==================== 确定性随机 ====================
local seed = 20261023

-- 固定种子 LCG，返回 0..1
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
end

-- 一维平滑值噪声：让曲线有起伏但不毛糙
local function hash1(n)
    local v = math.sin(n * 127.1) * 43758.5453
    return v - math.floor(v)
end

local function noise1(x)
    local i = math.floor(x)
    local f = x - i
    local u = f * f * (3 - 2 * f)
    return hash1(i) * (1 - u) + hash1(i + 1) * u
end

-- ==================== 缓冲尺寸 ====================
local N = 48          -- 主曲线点数（绘图侧再降采样到 18 / 11 / 9 点）
local NKPI = 12       -- KPI 迷你趋势点数
local NLINE = 5       -- 产线条数
local NALARM = 5      -- 告警行数
local NORDER = 3      -- 工单环数
local NDEV = 12       -- 设备矩阵格数
local NTL = 5         -- 时间轴节点数
local NPARETO = 8     -- 缺陷类别数
local HEAT_C, HEAT_R = 10, 4   -- 热力图列 x 行
local NTANK = 3       -- 储罐数

M.N = N

-- ==================== 数据容器 ====================
-- 趋势曲线：0..1 归一化，索引 1 = 最早，N = 最新
M.series = {
    cap = {}, t1 = {}, t2 = {}, t3 = {}, t4 = {}, energy = {}, unit = {},
}
-- 展示值（真实单位），与 series 同步推进
M.raw = { cap = 0, temp = 0, energy = 0, unit = 0 }

-- KPI：带单位的真实值
M.kpi = {
    oee = 87.4, output = 1284, yield = 99.2,
    plan = 1500, reject = 12, power = 386.5,
}
-- KPI 迷你趋势（0..1，各 NKPI 点）与达成率（0..1）
M.kpi_spark = { {}, {}, {} }
M.kpi_goal = { 0.92, 0.86, 0.98 }

-- 产线：state 1=运行 2=待机 3=告警 4=停机，cycle 0..1 节拍进度
M.lines = {}
-- 工单进度：v 0..1
M.orders = {}
-- 告警：level 1=提示 2=注意 3=严重
M.alarms = {}

-- 设备矩阵：state 1=运行 2=待机 3=告警 4=离线，load / health 0..1
M.dev = {}
-- 双针表读数（0..1）
M.meter = { vib = 0.42, temp = 0.58 }
-- 分段负载条（0..1）
M.loads = { 0.62, 0.45, 0.78 }
-- 设备状态时间轴：state 1=完成 2=当前 3=待办
M.tl = {}

-- 缺陷 Pareto：各类别占比 0..1（累计折线由绘图侧累加）
M.pareto = {}
-- 热力图：0..1，按列存（每列一个长度为 HEAT_R 的表）
M.heat = {}
-- 能耗双轴：柱状用电 / 折线单位能耗（用 series.energy / series.unit）
-- 储罐液位（0..1）
M.tank = {}
-- 水平刻度尺滑标位置（0..1）
M.ruler = 0.42

-- 时钟（用于顶栏 HUD）
M.clock = { h = 8, m = 30, s = 0 }

-- ==================== 初始化 ====================
local SERIES_CFG = {
    { key = "cap",    base = 0.58, amp = 0.20, sp = 0.24 },
    { key = "t1",     base = 0.52, amp = 0.16, sp = 0.19 },
    { key = "t2",     base = 0.47, amp = 0.18, sp = 0.13 },
    { key = "t3",     base = 0.60, amp = 0.14, sp = 0.27 },
    { key = "t4",     base = 0.41, amp = 0.20, sp = 0.16 },
    { key = "energy", base = 0.55, amp = 0.22, sp = 0.11 },
    { key = "unit",   base = 0.44, amp = 0.15, sp = 0.21 },
}

local LINE_SEED = {
    { name = "SMT-A", state = 1, wo = "WO-2610" },
    { name = "SMT-B", state = 1, wo = "WO-2611" },
    { name = "ASM-1", state = 2, wo = "WO-2612" },
    { name = "ASM-2", state = 1, wo = "WO-2613" },
    { name = "PKG-1", state = 3, wo = "WO-2614" },
}

local ORDER_SEED = {
    { name = "WO-2610", v = 0.72 },
    { name = "WO-2611", v = 0.54 },
    { name = "WO-2612", v = 0.31 },
}

local ALARM_SEED = {
    { level = 3, text = "PKG-1 主轴温度超限", src = "M09" },
    { level = 2, text = "空压机出口压力波动", src = "M07" },
    { level = 2, text = "ASM-1 节拍低于目标", src = "L03" },
    { level = 1, text = "冷却塔水位偏低",     src = "U01" },
    { level = 1, text = "工单 WO-2614 即将超时", src = "MES" },
}

local TL_SEED = {
    { name = "上料", state = 1 }, { name = "贴片", state = 1 },
    { name = "焊接", state = 1 }, { name = "组装", state = 2 },
    { name = "包装", state = 3 },
}

local TANK_SEED = {
    { name = "冷却水", v = 0.68 },
    { name = "液压油", v = 0.41 },
    { name = "原料仓", v = 0.83 },
}

--[[环形缓冲推一格：前面的值往前挪一位，新值落到末尾
@param table tbl 缓冲
@param number len 缓冲长度（必须与初始化时铺满的点数一致）
        写错会让表里出现空洞，绘图侧 fx.clamp(nil) 直接报错
@param number v 新值]]
local function push_series(tbl, len, v)
    for i = 1, len - 1 do tbl[i] = tbl[i + 1] end
    tbl[len] = v
end

--[[构建全部初始数据（开机调用一次）
曲线先用噪声铺满 N 点，避免开机时是空表、组件第一帧画不出线。]]
function M.init()
    seed = 20261023

    for _, cfg in ipairs(SERIES_CFG) do
        local t = M.series[cfg.key]
        for i = 1, N do
            local ph = i / N * 6.283 * cfg.sp * 4
            t[i] = cfg.base + cfg.amp * (noise1(i * 0.35) - 0.5) * 2
                + cfg.amp * 0.4 * math.sin(ph)
            if t[i] < 0.02 then t[i] = 0.02 end
            if t[i] > 0.98 then t[i] = 0.98 end
        end
    end

    for i = 1, 3 do
        local s = M.kpi_spark[i]
        for k = 1, NKPI do
            s[k] = 0.30 + 0.55 * noise1(k * 0.28 + i * 5.1)
        end
    end

    for i = 1, NLINE do
        local d = LINE_SEED[i]
        M.lines[i] = {
            name = d.name, state = d.state, wo = d.wo,
            cycle = 0.15 + rnd() * 0.7,
        }
    end

    for i = 1, NORDER do
        M.orders[i] = { name = ORDER_SEED[i].name, v = ORDER_SEED[i].v }
    end

    for i = 1, NALARM do
        M.alarms[i] = {
            level = ALARM_SEED[i].level, text = ALARM_SEED[i].text,
            src = ALARM_SEED[i].src, t = i * 47,
        }
    end

    for i = 1, NDEV do
        M.dev[i] = {
            tag = string.format("M%02d", i),
            state = (i % 5 == 0) and 3 or ((i % 4 == 0) and 2 or 1),
            load = 0.3 + rnd() * 0.6,
            health = 0.45 + rnd() * 0.5,
        }
    end

    for i = 1, NTL do
        M.tl[i] = { name = TL_SEED[i].name, state = TL_SEED[i].state }
    end

    for i = 1, NPARETO do
        M.pareto[i] = 0.18 + rnd() * 0.75
    end

    for c = 1, HEAT_C do
        local col = {}
        for r = 1, HEAT_R do
            col[r] = 0.15 + rnd() * 0.75
        end
        M.heat[c] = col
    end

    for i = 1, NTANK do
        M.tank[i] = { name = TANK_SEED[i].name, v = TANK_SEED[i].v }
    end

    M.clock = { h = 8, m = 30, s = 0 }
end

-- ==================== 推进 ====================
local simT = 0
local SAMPLE_SEC = 0.35
local sampleT = 0

--[[推进模拟数据
@param number dt 帧间隔秒
曲线以固定步长采样（SAMPLE_SEC），与 UI 帧率解耦。]]
function M.tick(dt)
    simT = simT + dt
    sampleT = sampleT + dt

    -- 时钟每秒走一格
    M.clock.s = M.clock.s + dt
    while M.clock.s >= 60 do
        M.clock.s = M.clock.s - 60
        M.clock.m = M.clock.m + 1
        if M.clock.m >= 60 then
            M.clock.m = 0
            M.clock.h = M.clock.h + 1
            if M.clock.h >= 24 then M.clock.h = 0 end
        end
    end

    -- 节拍进度：持续推进，到头就换下一张工单（模拟换型）
    for i = 1, NLINE do
        local d = M.lines[i]
        d.cycle = d.cycle + dt * (0.10 + 0.05 * i)
        if d.cycle > 1 then
            d.cycle = d.cycle - 1
        end
    end

    -- 工单进度缓慢推进
    for i = 1, NORDER do
        local o = M.orders[i]
        o.v = o.v + dt * 0.008 * (i == 1 and 1.4 or 1.0)
        if o.v > 0.99 then o.v = 0.12 end
    end

    -- 告警时间往前走（滚动列表看起来在"刷"）
    for i = 1, NALARM do
        M.alarms[i].t = M.alarms[i].t + dt
        if M.alarms[i].t > 400 then M.alarms[i].t = M.alarms[i].t - 400 end
    end

    -- 双针表：平滑趋近，指针"追"目标值
    M.meter.vib = 0.34 + 0.34 * (0.5 + 0.5 * math.sin(simT * 0.47))
    M.meter.temp = 0.42 + 0.36 * (0.5 + 0.5 * math.sin(simT * 0.29 + 1.9))

    -- 分段负载条
    for i = 1, 3 do
        local target = 0.35 + 0.5 * (0.5 + 0.5 * math.sin(simT * 0.36 + i * 1.3))
        M.loads[i] = M.loads[i] + (target - M.loads[i]) * math.min(1, dt * 1.8)
    end

    -- 设备矩阵：负载与健康度持续起伏
    for i = 1, NDEV do
        local d = M.dev[i]
        d.load = d.load + ((0.35 + 0.5 * (0.5 + 0.5 * math.sin(simT * 0.4 + i))) - d.load)
            * math.min(1, dt * 1.5)
        d.health = d.health + ((0.42 + 0.5 * (0.5 + 0.5 * math.sin(simT * 0.23 + i * 0.6))) - d.health)
            * math.min(1, dt * 1.2)
    end

    -- 储罐液位：缓慢升降，波浪相位由绘图侧按 t 走
    for i = 1, NTANK do
        local tk = M.tank[i]
        local target = 0.45 + 0.42 * (0.5 + 0.5 * math.sin(simT * 0.16 + i * 2.1))
        tk.v = tk.v + (target - tk.v) * math.min(1, dt * 1.1)
    end

    -- 刻度尺滑标：磁吸式缓慢漂移
    local rt = 0.30 + 0.55 * (0.5 + 0.5 * math.sin(simT * 0.18))
    M.ruler = M.ruler + (rt - M.ruler) * math.min(1, dt * 1.4)

    -- 曲线采样：到点才推一格
    if sampleT >= SAMPLE_SEC then
        sampleT = sampleT - SAMPLE_SEC
        for _, cfg in ipairs(SERIES_CFG) do
            local t = M.series[cfg.key]
            local v = cfg.base + cfg.amp * (noise1(simT * cfg.sp * 2 + cfg.base * 31) - 0.5) * 2
                + cfg.amp * 0.4 * math.sin(simT * cfg.sp)
            if v < 0.02 then v = 0.02 end
            if v > 0.98 then v = 0.98 end
            push_series(t, N, v)
        end
    end

    -- KPI 迷你趋势同步推一格
    for i = 1, 3 do
        local s = M.kpi_spark[i]
        push_series(s, NKPI, 0.30 + 0.55 * noise1(simT * 0.5 + i * 5.1))
    end

    -- 展示值由归一化值反算（单位换算只在这一处）
    M.raw.cap    = 80 + M.series.cap[N] * 320       -- 80..400 件/h
    M.raw.temp   = 28 + M.series.t1[N] * 42         -- 28..70 C
    M.raw.energy = 120 + M.series.energy[N] * 480   -- 120..600 kWh
    M.raw.unit   = 0.6 + M.series.unit[N] * 1.8     -- 0.6..2.4 kWh/件

    -- KPI 缓慢漂移
    M.kpi.oee = 82 + 8 * (0.5 + 0.5 * math.sin(simT * 0.12))
    M.kpi.output = 1180 + 220 * (0.5 + 0.5 * math.sin(simT * 0.09 + 1.1))
    M.kpi.yield = 98.4 + 1.2 * (0.5 + 0.5 * math.sin(simT * 0.15 + 2.2))
    M.kpi.power = 340 + 90 * (0.5 + 0.5 * math.sin(simT * 0.11 + 0.6))
end

-- ==================== 查询辅助 ====================

--[[取一条曲线
@param string key SERIES_CFG 里的 key
@return table 值数组（0..1），number 点数
]]
function M.get(key)
    return M.series[key], N
end

--[[格式化时钟
@return string "HH:MM:SS"
]]
function M.clock_str()
    return string.format("%02d:%02d:%02d", M.clock.h, M.clock.m, math.floor(M.clock.s))
end

return M
