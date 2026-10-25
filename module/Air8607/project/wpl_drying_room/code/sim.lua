--[[
@module  sim
@summary 烘干室模拟引擎：温度/湿度/含氧量/CO/CO2/含水率/水质 + 坚果库 + 设备 + 报警
@version 1.0
@date    2026.10.24

模拟规律：
  - 温度朝“坚果推荐温度中值”收敛（加热器开启），停机则朝室温回落；
  - 湿度/物料含水率随烘干进度下降，开启排湿后下降更快；
  - 含氧量由循环风机维持，风机关闭会轻微下降；
  - CO 由加热器燃烧产生，异常时短时升高（演示报警）；
  - 每隔一段时间随机注入异常，越限判 warn/danger 并记入报警。
]]
local conf = require "conf"

local M = {}
local math = math

local HISTORY_N = conf.sim.history_n

local DEFS = {
    temp  = { name = "温度",       unit = "°C",  dec = 1, base = 25,   jitter = 0.30, range = { 0, 100 },  low = 40, high = 70, dlow = 10, dhigh = 90 },
    hum   = { name = "湿度",       unit = "%",   dec = 0, base = 55,   jitter = 1.5,  range = { 0, 100 },  low = 20, high = 65, dhigh = 90 },
    o2    = { name = "含氧量",     unit = "%",   dec = 1, base = 20.9, jitter = 0.08, range = { 0, 25 },   low = 19, high = 23, dlow = 18, dhigh = 24 },
    co    = { name = "一氧化碳",   unit = "ppm", dec = 0, base = 5,    jitter = 1.5,  range = { 0, 200 },  high = 30, dhigh = 100 },
    co2   = { name = "二氧化碳",   unit = "ppm", dec = 0, base = 600,  jitter = 40,   range = { 0, 5000 }, high = 1500, dhigh = 3000 },
    moist = { name = "物料含水率", unit = "%",   dec = 1, base = 28,   jitter = 0.15, range = { 0, 40 },   low = 8,  high = 14, dhigh = 32 },
    ph    = { name = "水质 pH",    unit = "",    dec = 2, base = 7.2,  jitter = 0.04, range = { 4, 10 },   low = 6.5, high = 8.5, dlow = 6, dhigh = 9 },
    turb  = { name = "水质浊度",   unit = "NTU", dec = 0, base = 12,   jitter = 1.5,  range = { 0, 100 },  high = 25, dhigh = 50 },
}

local KEYS = { "temp", "hum", "o2", "co", "co2", "moist", "ph", "turb" }

local state = {
    values   = {},
    history  = {},
    status   = {},
    prev     = {},
    devices  = { heater = true, fan = true, vent = true, mute = false },
    alarms   = {},
    nut_index = 1,
    target_temp = 57,
    elapsed_min = 0,
    env      = { room = 26, out_hum = 52, press = 1008 },
    tick     = 0,
    paused   = false,
}

local manual = {}
local th_manual = {}
local drift = {}       -- 随机游走漂移，让波形有真实感（不是完美正弦）
local anomaly = nil

local function rnd() return (math.random() - 0.5) * 2 end

local function fmt_val(key, v)
    return string.format("%." .. DEFS[key].dec .. "f", v)
end

local function eff_th(key)
    local th = th_manual[key]
    local d = DEFS[key]
    return (th and th.low) or d.low, (th and th.high) or d.high
end

local function judge(key, v)
    local d = DEFS[key]
    local lo, hi = eff_th(key)
    if d.dhigh and v >= d.dhigh then return "danger" end
    if d.dlow and v <= d.dlow then return "danger" end
    if hi and v > hi then return "warn" end
    if lo and v < lo then return "warn" end
    return "normal"
end

local function push_alarm(key, level)
    local d = DEFS[key]
    local v = state.values[key]
    local text
    if level == "danger" then
        text = string.format("%s %s%s 触发报警", d.name, fmt_val(key, v), d.unit)
    else
        text = string.format("%s %s%s 偏离正常", d.name, fmt_val(key, v), d.unit)
    end
    table.insert(state.alarms, 1, { time = os.date("%H:%M"), level = level, key = key, text = text })
    if #state.alarms > conf.alarm.max_log then state.alarms[#state.alarms] = nil end
end

-- ==================== 初始 / 坚果切换 ====================
function M.init()
    local ok, seed = pcall(os.time)
    math.randomseed((ok and seed or 0) % 1000000 + 1)
    for _, key in ipairs(KEYS) do
        local d = DEFS[key]
        state.values[key] = d.base
        state.status[key] = "normal"
        state.prev[key] = "normal"
        state.history[key] = {}
        for i = 1, HISTORY_N do
            state.history[key][i] = d.base + rnd() * d.jitter * 0.3
        end
    end
    M.set_nut(1)
    M.compute_env()
end

--[[切换坚果：更新推荐温度区间 + 目标温度，重置本批烘干进度]]
function M.set_nut(index)
    local nut = conf.nuts[index]
    if not nut then return end
    state.nut_index = index
    state.target_temp = (nut.temp_min + nut.temp_max) / 2
    th_manual.temp = { low = nut.temp_min, high = nut.temp_max }
    state.elapsed_min = 0
    manual.temp = nil
    -- 温度直接到位，并把波形历史也重置到目标温度：
    -- 否则历史里会留着“从室温爬升”的陡线，把自适应 y 轴撑大，波形被压成平线
    state.values.temp = state.target_temp
    state.history.temp = {}
    for i = 1, HISTORY_N do
        state.history.temp[i] = state.target_temp
    end
end

function M.nut() return conf.nuts[state.nut_index] end
function M.nut_index() return state.nut_index end
function M.target_temp() return state.target_temp end

function M.progress()
    local nut = M.nut()
    local total = nut.hours * 60
    if total <= 0 then return 0 end
    local p = state.elapsed_min / total
    if p > 1 then p = 1 end
    return p
end
function M.elapsed_min() return state.elapsed_min end
function M.total_min() return M.nut().hours * 60 end

-- ==================== 每 tick 刷新 ====================
function M.set_paused(b) state.paused = b end
function M.paused() return state.paused end

function M.tick()
    if state.paused then return end
    state.tick = state.tick + 1

    local nut = M.nut()
    state.elapsed_min = state.elapsed_min + conf.sim.dry_minutes_per_tick
    if state.elapsed_min > nut.hours * 60 then state.elapsed_min = nut.hours * 60 end
    local prog = M.progress()

    -- 异常注入
    if anomaly then
        anomaly.remaining = anomaly.remaining - 1
        if anomaly.remaining <= 0 then anomaly = nil end
    elseif state.tick % conf.alarm.anomaly_every == 0 then
        local pool = { "co", "temp", "o2", "moist", "turb" }
        local key = pool[math.random(#pool)]
        if not manual[key] then
            anomaly = { key = key, dir = (math.random(2) == 1) and 1 or -1, remaining = conf.alarm.anomaly_ticks }
        end
    end

    for i, key in ipairs(KEYS) do
        local d = DEFS[key]
        local v = state.values[key]

        local target
        if manual[key] then
            target = manual[key]
        else
            if key == "temp" then
                target = state.devices.heater and state.target_temp or conf.sim.room_temp
            elseif key == "hum" then
                target = 55 - 35 * prog
                if state.devices.vent then target = target - 8 end
            elseif key == "moist" then
                target = 28 - 18 * prog
            elseif key == "o2" then
                target = state.devices.fan and 20.9 or 19.2
            elseif key == "co" then
                target = state.devices.heater and 6 or 2
            elseif key == "co2" then
                target = 500 + 900 * prog
                if not state.devices.fan then target = target + 500 end
            elseif key == "ph" then
                target = 7.2
            elseif key == "turb" then
                target = 12
            else
                target = d.base
            end

            if anomaly and anomaly.key == key then
                local amp = (key == "temp") and 22 or (key == "co") and 90 or
                            (key == "o2") and 3 or (key == "moist") and 8 or
                            (key == "turb") and 30 or 0.5
                -- 正弦包络：异常平滑升起再回落，避免波形上出现突兀的斜线跳变
                local total_t = conf.alarm.anomaly_ticks
                local done = total_t - anomaly.remaining
                local k = done / total_t
                if k < 0 then k = 0 end
                if k > 1 then k = 1 end
                local env = math.sin(k * math.pi)
                target = target + anomaly.dir * amp * env
            end
        end

        -- 自然波动：两条不同频率的正弦叠加，让波形有节奏起伏（不是一条直线）
        local phase = i * 1.7
        target = target + math.sin(state.tick / 5.0 + phase) * d.jitter * 2.5
                        + math.sin(state.tick / 13.0 + phase * 0.6) * d.jitter * 1.5
                        + math.sin(state.tick / 2.3 + phase * 1.3) * d.jitter * 0.6

        -- 随机游走漂移：叠加在正弦上，波形更像真实传感器而不是平滑正弦
        local dr = (drift[key] or 0) * 0.90 + rnd() * d.jitter * 1.2
        drift[key] = dr
        target = target + dr

        local speed = (key == "temp") and 0.18 or 0.12
        v = v + (target - v) * speed + rnd() * d.jitter
        if v < 0 then v = 0 end
        state.values[key] = v

        local his = state.history[key]
        his[#his + 1] = v
        if #his > HISTORY_N then table.remove(his, 1) end

        local st = judge(key, v)
        if st ~= state.prev[key] then
            if st ~= "normal" then push_alarm(key, st) end
            state.prev[key] = st
        end
        state.status[key] = st
    end

    M.compute_env()
end

function M.compute_env()
    state.env.room = conf.sim.room_temp + rnd() * 1.5
    state.env.out_hum = 52 + rnd() * 6
    state.env.press = 1008 + rnd() * 3
end

function M.feeding() end  -- 兼容占位（本场景不使用）

-- ==================== 交互 ====================
function M.set_value(key, v)
    if not DEFS[key] then return end
    manual[key] = v
    state.values[key] = v
    -- 立即把波形历史也填成新值：否则历史里会留着“从旧值收敛到新值”的过程，
    -- 显示出来就是一条斜线（用户看到的就是这个）
    local his = state.history[key]
    if his then
        for i = 1, #his do his[i] = v end
    end
    drift[key] = 0
end

function M.is_manual(key) return manual[key] ~= nil end
function M.manual(key) return manual[key] end
function M.clear_manual(key) manual[key] = nil end
function M.range(key) return DEFS[key].range end

function M.set_threshold(key, low, high)
    th_manual[key] = { low = low, high = high }
end

function M.threshold(key) return eff_th(key) end

function M.toggle_device(key)
    if state.devices[key] == nil then return end
    state.devices[key] = not state.devices[key]
    return state.devices[key]
end

-- ==================== 对外读取 ====================
function M.tick_count() return state.tick end
function M.keys() return KEYS end
function M.def(key) return DEFS[key] end
function M.get(key) return state.values[key] end
function M.status(key) return state.status[key] end
function M.history(key) return state.history[key] end
function M.fmt(key, v) return fmt_val(key, v or state.values[key]) end
function M.devices() return state.devices end
function M.alarms() return state.alarms end
function M.env() return state.env end
function M.any_alarm()
    for _, key in ipairs(KEYS) do
        if state.status[key] ~= "normal" then return true end
    end
    return false
end

return M
