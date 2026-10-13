--[[
@module  mock_data
@summary VOCs 监测数据模型（模拟数据源 / 业务逻辑层）
@version 1.0.0
@date    2026.10.10
@usage
本模块是「数据 / 逻辑」与「界面」的解耦层：
  - 周期性刷新内部状态，并通过 sys.publish("VOCS_DATA") 广播快照；
  - 界面层只订阅消息、只读快照，绝不自行计算数据；
  - 设置项修改（步进器 / 开关 / 载气 / 协议）统一走本模块接口，
    改完立即重新广播，保证「数据是唯一事实来源」。
接口：
  mock_data.init()                 -- 启动数据刷新任务
  mock_data.get()                  -- 取当前快照表
  mock_data.step_param(key, dir)   -- 步进修改色谱方法参数（dir=1/-1）
  mock_data.set_switch(key, on)    -- 修改开关
  mock_data.set_carrier(name)      -- 修改载气
  mock_data.set_protocol(name)     -- 修改通信协议
]]

local config = require "config"

local M = {}

-- ================= 静态基础数据 =================
-- 色谱峰（相对位置 / 相对强度 / 峰宽 / 名称），取自设计稿
local CHROM_PEAKS = {
    { x = 0.055, h = 0.17 },
    { x = 0.115, h = 0.40 },
    { x = 0.190, h = 0.26 },
    { x = 0.270, h = 0.64, name = "苯" },
    { x = 0.355, h = 0.21 },
    { x = 0.440, h = 0.86, name = "甲苯" },
    { x = 0.540, h = 0.29 },
    { x = 0.628, h = 0.51, name = "乙苯" },
    { x = 0.715, h = 0.36 },
    { x = 0.806, h = 0.58, name = "二甲苯" },
    { x = 0.900, h = 0.23 },
}
-- 峰宽单独一张表（与 CHROM_PEAKS 顺序对应）
local CHROM_WIDTH = { 0.0055, 0.0075, 0.0065, 0.0085, 0.0060, 0.0092,
                      0.0068, 0.0085, 0.0075, 0.0088, 0.0065 }

-- 质谱特征峰强度（m/z -> 相对强度），未列出的按伪随机噪声生成
local MS_BASE = {
    [18]=0.14,[27]=0.09,[28]=0.21,[29]=0.11,[38]=0.07,[39]=0.25,[50]=0.13,
    [51]=0.29,[52]=0.15,[62]=0.09,[63]=0.12,[65]=0.19,[74]=0.17,[77]=0.42,
    [78]=1.00,[79]=0.11,[89]=0.15,[91]=0.78,[92]=0.21,[103]=0.11,[104]=0.14,
    [105]=0.29,[106]=0.33,[107]=0.10,[118]=0.08,[119]=0.10,[120]=0.13,
}

-- 峰识别结果（色谱视图右栏）
local PEAKS_TABLE = {
    { idx=1,  rt="0.86", nm="丙酮",     mt=86, level="mid" },
    { idx=2,  rt="1.42", nm="异戊二烯", mt=91, level="mid" },
    { idx=3,  rt="2.35", nm="苯",       mt=98, level="high" },
    { idx=4,  rt="3.68", nm="甲苯",     mt=99, level="high" },
    { idx=5,  rt="4.51", nm="乙苯",     mt=96, level="high" },
    { idx=6,  rt="5.02", nm="对二甲苯", mt=94, level="high" },
    { idx=7,  rt="5.44", nm="间二甲苯", mt=92, level="mid" },
    { idx=8,  rt="5.89", nm="邻二甲苯", mt=89, level="mid" },
    { idx=9,  rt="6.72", nm="苯乙烯",   mt=88, level="mid" },
    { idx=10, rt="7.60", nm="萘",       mt=84, level="low" },
    { idx=11, rt="8.45", nm="正十一烷", mt=81, level="low" },
}

-- 主要离子（质谱视图右栏）
-- 注：hzfont 不含上下标与间隔号，统一用 ASCII 表达
local IONS_TABLE = {
    { idx=1,  mz="78",  nm="苯 M+",        ab=100, level="high" },
    { idx=2,  mz="91",  nm="甲苯 M-1",     ab=78,  level="high" },
    { idx=3,  mz="106", nm="二甲苯 M+",    ab=33,  level="mid" },
    { idx=4,  mz="77",  nm="苯基碎片",     ab=42,  level="mid" },
    { idx=5,  mz="51",  nm="C4H3+",        ab=29,  level="mid" },
    { idx=6,  mz="39",  nm="C3H3+",        ab=25,  level="low" },
    { idx=7,  mz="105", nm="C8H9+",        ab=29,  level="low" },
    { idx=8,  mz="28",  nm="N2 / CO",      ab=21,  level="low" },
    { idx=9,  mz="92",  nm="甲苯同位素",   ab=21,  level="low" },
    { idx=10, mz="65",  nm="C5H5+",        ab=19,  level="low" },
    { idx=11, mz="74",  nm="背景组分",     ab=17,  level="low" },
}

-- 事件流（数据视图右栏）
local EVENTS = {
    { time="14:22", level="warn", text="苯浓度 12.4 ug/m3 超出阈值" },
    { time="13:05", level="ok",   text="自动校准完成，偏差 0.4%" },
    { time="12:48", level="info", text="方法 VOC-58 已加载" },
    { time="11:30", level="warn", text="甲苯浓度短时升高 15.2 ug/m3" },
    { time="10:12", level="ok",   text="数据已同步至云端（1.2 MB）" },
    { time="09:00", level="info", text="系统启动自检通过" },
}

-- ================= 运行时状态 =================
local state = {}

local function clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

local function rnd(lo, hi)
    return lo + math.random() * (hi - lo)
end

-- 伪随机（确定性），用于生成质谱背景噪声
local function ms_rnd(n)
    local x = math.sin(n * 127.1 + 311.7) * 43758.5453
    return x - math.floor(x)
end

-- ================= 趋势曲线参数 =================
-- 三条系列用「基值 + 双正弦慢波 + 小幅噪声」，围绕各自基值起伏。
-- 注意不要用「随机游走 + clamp」：游走会长时间贴在限幅下沿（实测三条线
-- 只用到 2..9），在 0..24 的 Y 轴上只占底部一小条，肉眼看不出起伏。
local TREND_BASE = { 6, 10, 14 }      -- 苯 / 甲苯 / TVOC 的基值
local TREND_AMP  = { 3.2, 3.4, 4.0 }  -- 各系列慢波幅度
local TREND_LO, TREND_HI = 2, 20      -- 硬限幅，保证落在 Y 轴范围内

-- 生成一个趋势采样点；必须返回整数：
-- airui.chart 的数值走 lua_tointeger，带小数的浮点会被判为 0
local function trend_point(si, seq)
    local w = math.sin(seq * 0.19 + si * 1.7) * 0.6
            + math.sin(seq * 0.047 + si * 0.8) * 0.4
    local v = TREND_BASE[si] + w * TREND_AMP[si] + rnd(-0.9, 0.9)
    return math.floor(clamp(v, TREND_LO, TREND_HI) + 0.5)
end

-- 色谱信号：高斯峰叠加 + 三路正弦噪声（对应设计稿 chromSignal）
local function chrom_signal(x, t)
    local v = 0.013
    for i = 1, #CHROM_PEAKS do
        local p = CHROM_PEAKS[i]
        local d = (x - p.x) / CHROM_WIDTH[i]
        v = v + p.h * math.exp(-0.5 * d * d)
    end
    v = v + math.sin(x * 173 + t * 0.0011) * 0.0042
    v = v + math.sin(x * 389 - t * 0.0017) * 0.0026
    v = v + math.sin(x * 71 + t * 0.0007) * 0.0032
    if v < 0 then v = 0 end
    return v
end

-- 生成一帧色谱曲线（整型 0..1000，供 airui.chart 使用）
local function build_chrom(t)
    local n = config.data.chrom_points
    local out = {}
    for i = 1, n do
        local x = (i - 1) / (n - 1)
        local v = chrom_signal(x, t)
        out[i] = math.floor(math.min(v, 1) * 1000 + 0.5)
    end
    return out
end

-- 生成一帧质谱柱状数据
local function build_ms(t)
    local bars = {}
    for mz = 12, 130 do
        local v0 = MS_BASE[mz]
        if not v0 then
            v0 = ms_rnd(mz) * 0.078 * (1 - (mz - 12) / 160)
        end
        if v0 > 0.014 then
            local flick = 1 + math.sin(t * 0.0012 + mz * 0.73) * 0.055
            bars[#bars + 1] = { mz = mz, v = clamp(v0 * flick, 0, 1) }
        end
    end
    return bars
end

-- 初始化状态
local function reset_state()
    state.clock       = os.date("%H:%M:%S")
    state.running     = true
    state.method      = config.method
    state.firmware    = config.firmware
    state.eth         = "已连接"
    state.status_ok   = true
    state.scan_no     = 1042
    state.temp        = 42.6
    state.vacuum      = "3.2×10-6 Pa"
    state.tick        = 0
    state.ms_scan     = "SCAN 1042"

    state.metrics = { tic = 1.24, cmp = 8, cyc = 63, pre = 62.4 }

    state.vocs = {
        { name = "苯",     val = 12.4 },
        { name = "甲苯",   val = 8.6 },
        { name = "乙苯",   val = 3.2 },
        { name = "二甲苯", val = 5.1 },
    }

    state.chrom       = build_chrom(0)
    state.chrom_peaks = CHROM_PEAKS
    state.ms          = build_ms(0)

    -- 趋势曲线：三条系列共用同一时间基准 seq，仅相位不同
    state.trend = { { name = "苯", data = {} }, { name = "甲苯", data = {} }, { name = "TVOC", data = {} } }
    for seq = 1, config.data.trend_points do
        for si = 1, 3 do
            state.trend[si].data[seq] = trend_point(si, seq)
        end
    end
    state.trend_seq = config.data.trend_points

    state.stat        = { avg = 9.8, peak = 18.6, over = 3, rate = 99.2 }
    state.events      = EVENTS
    state.peaks_table = PEAKS_TABLE
    state.ions_table  = IONS_TABLE

    state.params   = {}
    for k, v in pairs(config.params) do state.params[k] = v end
    state.switches = {}
    for k, v in pairs(config.switches) do state.switches[k] = v end
    state.carrier  = config.params.carrier
    state.protocol = "Modbus"
end

-- 单帧刷新（UI 无关，纯数据推进）
local function tick()
    state.tick = state.tick + 1
    local t = state.tick * config.data.tick_ms

    -- 时钟
    state.clock = os.date("%H:%M:%S")

    -- 指标
    local m = state.metrics
    m.tic = clamp(m.tic + rnd(-0.0275, 0.0275), 1.04, 1.48)
    if math.random() < 0.07 then
        m.cmp = clamp(m.cmp + (math.random() < 0.5 and -1 or 1), 5, 12)
    end
    m.cyc = m.cyc + 0.9
    if m.cyc > 100 then m.cyc = 2 end
    m.pre = clamp(m.pre + rnd(-0.175, 0.175), 60.5, 64.5)
    state.temp = clamp(state.temp + rnd(-0.125, 0.125), 41.8, 43.6)

    -- 组分浓度
    for i = 1, #state.vocs do
        local row = state.vocs[i]
        row.val = clamp(row.val + rnd(-0.225, 0.225), 1.0, 18)
    end

    -- 色谱 / 质谱
    state.chrom = build_chrom(t)
    state.ms = build_ms(t)

    -- 扫描号
    state.scan_no = state.scan_no + math.random(1, 3)
    if state.scan_no > 9999 then state.scan_no = 1 end
    state.ms_scan = string.format("SCAN %04d", state.scan_no)

    -- 趋势：每 trend_period 个 tick 追加一个点
    if state.tick % config.data.trend_period == 0 then
        state.trend_seq = state.trend_seq + 1
        for si = 1, #state.trend do
            local s = state.trend[si]
            s.data[#s.data + 1] = trend_point(si, state.trend_seq)
            if #s.data > config.data.trend_points then
                table.remove(s.data, 1)
            end
        end
    end

    sys.publish("VOCS_DATA", state)
end

-- ================= 对外接口 =================
function M.get()
    return state
end

function M.init()
    math.randomseed(os.time())
    reset_state()
    log.info("mock_data", "数据层初始化完成")
    sys.taskInit(function()
        -- 先发一帧，保证界面首屏即有数据
        sys.publish("VOCS_DATA", state)
        while true do
            sys.wait(config.data.tick_ms)
            tick()
        end
    end)
end

-- 步进修改色谱方法参数（设置页专用）
function M.step_param(key, dir)
    local spec = config.param_spec[key]
    if not spec then return end
    local v = state.params[key] or spec.min
    v = clamp(v + dir * spec.step, spec.min, spec.max)
    state.params[key] = v
    sys.publish("VOCS_DATA", state)
end

function M.set_switch(key, on)
    state.switches[key] = on and true or false
    sys.publish("VOCS_DATA", state)
end

function M.set_carrier(name)
    state.carrier = name
    state.params.carrier = name
    sys.publish("VOCS_DATA", state)
end

function M.set_protocol(name)
    state.protocol = name
    sys.publish("VOCS_DATA", state)
end

return M
