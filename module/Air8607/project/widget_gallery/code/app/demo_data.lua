--[[
@module  demo_data
@summary WIDGET GALLERY - 组件橱窗模拟数据源（曲线缓冲 / 状态 / 告警 / KPI）
@version 1.0
@date    2026.10.23
@author  江访

=== 这一层解决什么 ===
橱窗里的组件要"在动"才看得出效果，但数据本身不是本工程的重点。
所以把所有假数据收在一个文件里：UI 只读字段、不关心来源，
真机联调时把 D.tick 换成真实采集回调即可，组件代码一行不用改。

=== 为什么用自带 LCG 而不是 math.random ===
math.random 的种子受平台实现影响，每次开机画面都不一样，
截图/比对/复现问题全都做不到。这里用固定种子的 LCG，
每次上电生成的序列完全一致。

=== 值域约定 ===
所有"给图元画的"量都是 0..1 归一化值（D.series / D.bar / D.gauge / D.load），
所有"给 label 显示的"量都是带单位的真实值（D.kpi / D.raw）。
这样绘图代码里不需要再做量程换算，单位换算只发生在这里一处。
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
local N = 48          -- 趋势曲线点数（对应卡片内容区宽度约 300px，每点 6px）
local HBARS = 10      -- 柱状图柱数
local NMAT = 12       -- 设备矩阵格数
local NALARM = 5      -- 告警列表行数
local NRADAR = 6      -- 雷达轴数
local HEAT_C, HEAT_R = 12, 4   -- 热力图列 x 行

M.N = N

-- ==================== 数据容器 ====================
-- 趋势曲线：0..1 归一化，索引 1 = 最早，N = 最新
M.series = {
    temp  = {}, hum = {}, co2 = {}, lux = {}, flow = {}, power = {},
}
-- 展示值（真实单位），与 series 同步推进
M.raw = { temp = 0, hum = 0, co2 = 0, lux = 0, flow = 0, power = 0 }

-- 仪表读数：0..1
M.gauge = { a = 0.62, b = 0.48, c = 0.71, d = 0.35 }

-- 柱状：0..1
M.bar = {}
-- 火花线组：4 条，各 N 点
M.spark = { {}, {}, {}, {} }

-- 设备矩阵：state 1=运行 2=待机 3=告警 4=离线，load 0..1
M.dev = {}
-- 告警：level 1=提示 2=注意 3=严重
M.alarms = {}
-- 雷达轴：0..1
M.radar = {}
-- 热力图：0..1，按列存（每列一个长度为 HEAT_R 的表）
M.heat = {}

-- KPI：带单位的真实值
M.kpi = {
    oee = 87.4, output = 1284, yield = 99.2,
    cycle = 42.6, energy = 386.5, down = 12,
}

-- 时钟（用于顶栏与时间轴）
M.clock = { h = 8, m = 30, s = 0 }

-- ==================== 初始化 ====================
local SERIES_CFG = {
    { key = "temp",  base = 0.55, amp = 0.18, sp = 0.22 },
    { key = "hum",   base = 0.62, amp = 0.14, sp = 0.17 },
    { key = "co2",   base = 0.44, amp = 0.22, sp = 0.11 },
    { key = "lux",   base = 0.50, amp = 0.26, sp = 0.29 },
    { key = "flow",  base = 0.58, amp = 0.16, sp = 0.35 },
    { key = "power", base = 0.48, amp = 0.20, sp = 0.13 },
}

local function push_series(tbl, v)
    for i = 1, N - 1 do tbl[i] = tbl[i + 1] end
    tbl[N] = v
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

    for i = 1, HBARS do
        M.bar[i] = 0.25 + rnd() * 0.6
    end

    for k = 1, 4 do
        local s = M.spark[k]
        for i = 1, N do
            s[i] = 0.35 + 0.4 * noise1(i * 0.22 + k * 7.3)
        end
    end

    for i = 1, NMAT do
        M.dev[i] = {
            state = (i % 5 == 0) and 3 or ((i % 4 == 0) and 2 or 1),
            load = 0.3 + rnd() * 0.6,
            tag = string.format("M%02d", i),
        }
    end

    local ALARM_SEED = {
        { level = 3, text = "3号工位主轴温度超限", src = "M03" },
        { level = 2, text = "空压机出口压力波动", src = "M07" },
        { level = 2, text = "输送线节拍低于目标", src = "L02" },
        { level = 1, text = "冷却塔水位偏低", src = "U01" },
        { level = 1, text = "工单 WO-2610 即将超时", src = "MES" },
    }
    for i = 1, NALARM do
        M.alarms[i] = ALARM_SEED[i]
        M.alarms[i].t = i * 47   -- 相对时间戳（秒前）
    end

    for i = 1, NRADAR do
        M.radar[i] = 0.35 + rnd() * 0.5
    end

    for c = 1, HEAT_C do
        local col = {}
        for r = 1, HEAT_R do
            col[r] = 0.15 + rnd() * 0.75
        end
        M.heat[c] = col
    end

    M.clock = { h = 8, m = 30, s = 0 }
end

-- ==================== 推进 ====================
local simT = 0

--[[推进模拟数据
@param number dt 帧间隔秒
曲线以固定步长采样（SAMPLE_SEC），与 UI 帧率解耦：
跑 20fps 和 30fps 时曲线推进速度一致。]]
local SAMPLE_SEC = 0.35
local sampleT = 0
local alarmT = 0

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

    -- 仪表 / 火花线 / 柱状 / 雷达：每帧平滑趋近，肉眼才连贯
    local breathe = 0.5 + 0.5 * math.sin(simT * 0.6)
    M.gauge.a = 0.52 + 0.30 * (0.5 + 0.5 * math.sin(simT * 0.45))
    M.gauge.b = 0.42 + 0.26 * (0.5 + 0.5 * math.sin(simT * 0.31 + 1.7))
    M.gauge.c = 0.55 + 0.34 * (0.5 + 0.5 * math.sin(simT * 0.22 + 3.1))
    M.gauge.d = 0.30 + 0.45 * breathe

    for i = 1, HBARS do
        local target = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(simT * 0.5 + i * 0.7))
        M.bar[i] = M.bar[i] + (target - M.bar[i]) * math.min(1, dt * 2.2)
    end

    for k = 1, 4 do
        local s = M.spark[k]
        local last = s[N] or 0.5
        local target = 0.35 + 0.4 * noise1(simT * (0.6 + k * 0.13) + k * 7.3)
        s[N] = last + (target - last) * math.min(1, dt * 3)
    end

    for i = 1, NRADAR do
        local target = 0.35 + 0.5 * (0.5 + 0.5 * math.sin(simT * (0.2 + i * 0.07) + i))
        M.radar[i] = M.radar[i] + (target - M.radar[i]) * math.min(1, dt * 1.8)
    end

    -- 设备矩阵：状态偶尔翻转，负载持续起伏
    --[[状态只由 simT 推，不消耗 LCG：伪随机序列一旦按帧数消费，
    换个帧率画面就变了，"每次上电一模一样"这条就没了。]]
    for i = 1, NMAT do
        local d = M.dev[i]
        d.load = d.load + ((0.35 + 0.5 * (0.5 + 0.5 * math.sin(simT * 0.4 + i))) - d.load)
            * math.min(1, dt * 1.5)

        local w = 0.5 + 0.5 * math.sin(simT * (0.11 + (i % 5) * 0.023) + i * 1.9)
        if w > 0.86 then
            d.state = 4                    -- 离线
        elseif w > 0.76 then
            d.state = 3                    -- 告警
        elseif w > 0.42 then
            d.state = 1                    -- 运行
        else
            d.state = 2                    -- 待机
        end
    end

    -- 告警：相对时间每秒走一格（列表文案不动，只动"多少秒前"）
    alarmT = alarmT + dt
    if alarmT >= 1 then
        alarmT = alarmT - 1
        for i = 1, #M.alarms do
            M.alarms[i].t = M.alarms[i].t + 1
        end
    end

    -- 曲线采样：到点才推一格
    if sampleT >= SAMPLE_SEC then
        sampleT = sampleT - SAMPLE_SEC
        for _, cfg in ipairs(SERIES_CFG) do
            local t = M.series[cfg.key]
            local v = cfg.base + cfg.amp * (noise1(simT * cfg.sp * 2 + cfg.base * 31) - 0.5) * 2
                + cfg.amp * 0.4 * math.sin(simT * cfg.sp)
            if v < 0.02 then v = 0.02 end
            if v > 0.98 then v = 0.98 end
            push_series(t, v)
        end
        -- 火花线组同步推一格
        for k = 1, 4 do
            local s = M.spark[k]
            push_series(s, s[N])
        end
    end

    -- 展示值由归一化值反算（单位换算只在这一处）
    M.raw.temp  = 18 + M.series.temp[N]  * 16        -- 18..34 C
    M.raw.hum   = 35 + M.series.hum[N]   * 55        -- 35..90 %
    M.raw.co2   = 400 + M.series.co2[N]  * 1000      -- 400..1400 ppm
    M.raw.lux   = M.series.lux[N]        * 120       -- 0..120 klx
    M.raw.flow  = M.series.flow[N]       * 60        -- 0..60 m3/h
    M.raw.power = 80 + M.series.power[N] * 320       -- 80..400 kW

    -- KPI 缓慢漂移
    M.kpi.oee = 82 + 8 * (0.5 + 0.5 * math.sin(simT * 0.12))
    M.kpi.cycle = 40 + 5 * (0.5 + 0.5 * math.sin(simT * 0.19 + 1.2))
    M.kpi.energy = 360 + 60 * (0.5 + 0.5 * math.sin(simT * 0.09 + 2.4))
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
