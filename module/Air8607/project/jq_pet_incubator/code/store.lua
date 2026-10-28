--[[
@module  store
@summary 宠物恒温箱数据层：房间 / 设备 / 阈值 / 模拟传感器 / 报警判定
@version 1.0
@date    2026.10.28

内部指标键（避免和字段名冲突）：
  t = 温度(℃)   h = 湿度(%)   g = 有毒气体(ppm)

模拟规律：
  - 暖风开启温度上冲、冷风开启温度回落，两者都关时缓慢回落到室温；
  - 湿度与温度反向（暖风降湿、冷风增湿）；
  - 有毒气体缓慢累积，灯光开启时略降（催化分解的演示语义）；
  - 每 anomaly_every 个 tick 随机挑一台设备注入一次正弦包络异常，用来演示报警。
]]
local conf = require "conf"

local M = {}
local HN = conf.sim.history_n
local LIM = conf.limits

local S = {
    rooms    = {},
    devices  = {},
    next_id  = 1,
    next_rid = 1,
    tick     = 0,
    alarms   = {},
    anomaly  = nil,
}

M.DEC   = { t = 1, h = 0, g = 1 }
M.UNIT  = { t = "℃", h = "%", g = "ppm" }
M.NAME  = { t = "温度", h = "湿度", g = "有毒气体" }
M.ORDER = { "t", "h", "g" }

M.PET_COLOR = {
    chick   = 0xFFD166,
    cat     = 0xFFB0C7,
    rabbit  = 0xDCD3FF,
    bear    = 0xD9AE86,
    hamster = 0xFFC3D6,
}
M.PET_KIND  = { "chick", "cat", "rabbit", "bear", "hamster" }
M.PET_LABEL = { chick = "小鸡", cat = "小猫", rabbit = "兔子", bear = "小熊", hamster = "仓鼠" }

local judge   -- 前向声明：设备创建时就要用到

local function rnd(a, b) return a + math.random() * (b - a) end

local function push_hist(h, v)
    h[#h + 1] = v
    while #h > HN do table.remove(h, 1) end
end

function M.fmt(key, v)
    return string.format("%." .. M.DEC[key] .. "f", v or 0)
end

--------------------------------------------------------------------
-- 房间
--------------------------------------------------------------------
function M.rooms() return S.rooms end

function M.room(id)
    for _, r in ipairs(S.rooms) do
        if r.id == id then return r end
    end
end

function M.room_name(id)
    local r = M.room(id)
    return r and r.name or "未分组"
end

function M.add_room(name)
    local r = { id = S.next_rid, name = name }
    S.next_rid = S.next_rid + 1
    S.rooms[#S.rooms + 1] = r
    return r
end

function M.room_count(id)
    local n = 0
    for _, d in ipairs(S.devices) do
        if d.room == id then n = n + 1 end
    end
    return n
end

--------------------------------------------------------------------
-- 设备
--------------------------------------------------------------------
function M.devices() return S.devices end

function M.get(id)
    if id == nil then return nil end
    for _, d in ipairs(S.devices) do
        if d.id == id then return d end
    end
    return nil
end

function M.count() return #S.devices end

function M.add_device(name, pet, room_id)
    if #S.devices >= conf.max_devices then return nil end
    local d = {
        id    = S.next_id,
        name  = name,
        pet   = pet,
        room  = room_id,
        temp  = rnd(27.2, 28.8),
        hum   = rnd(50, 62),
        gas   = rnd(0.6, 1.8),
        th = {
            t_lo = LIM.temp.def_low, t_hi = LIM.temp.def_high,
            h_lo = LIM.hum.def_low,  h_hi = LIM.hum.def_high,
            g_hi = LIM.gas.def_high,
        },
        dev = { warm = false, cool = false, light = true },
        hist = { t = {}, h = {}, g = {} },
        st = { any = false, t = false, h = false, g = false },
        hold = 0,   -- 异常包络进度（0 表示无异常）
    }
    S.next_id = S.next_id + 1

    for i = 1, HN do
        d.hist.t[i] = d.temp + rnd(-0.25, 0.25)
        d.hist.h[i] = d.hum + rnd(-1.2, 1.2)
        local g = d.gas + rnd(-0.25, 0.25)
        if g < 0 then g = 0 end
        d.hist.g[i] = g
    end

    S.devices[#S.devices + 1] = d
    judge(d, true)
    return d
end

-- 改名：重名时自动追加序号
function M.rename(d, name)
    if not d or not name or name == "" then return false end
    local nm = name
    local dup = 0
    for _, o in ipairs(S.devices) do
        if o ~= d and o.name == nm then dup = dup + 1 end
    end
    if dup > 0 then nm = nm .. " " .. (dup + 1) end
    d.name = nm
    return true
end

function M.remove_device(id)
    for i, d in ipairs(S.devices) do
        if d.id == id then
            table.remove(S.devices, i)
            return true
        end
    end
    return false
end

-- 当前房间筛选下的设备列表（0 = 全部）
function M.list(room_id)
    if not room_id or room_id == 0 then return S.devices end
    local out = {}
    for _, d in ipairs(S.devices) do
        if d.room == room_id then out[#out + 1] = d end
    end
    return out
end

--------------------------------------------------------------------
-- 阈值
--------------------------------------------------------------------
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- key: t/h/g  which: "lo"/"hi"  dir: -1/+1
function M.step_th(d, key, which, dir)
    if not d then return end
    local lim
    if key == "t" then lim = LIM.temp elseif key == "h" then lim = LIM.hum else lim = LIM.gas end
    local step = lim.step * dir
    local field = key .. "_" .. which
    local v = (d.th[field] or 0) + step
    v = clamp(v, lim.min, lim.max)

    if which == "lo" then
        local hi_key = key .. "_hi"
        local hi = d.th[hi_key]
        if hi and v > hi - lim.step then v = hi - lim.step end
        d.th[field] = v
    else
        local lo_key = key .. "_lo"
        local lo = d.th[lo_key]
        if lo and v < lo + lim.step then v = lo + lim.step end
        d.th[field] = v
    end

    judge(d, true)
    return v
end

-- 详情页用的完整阈值描述
function M.th_range_text(d, key)
    if key == "g" then
        return "报警上限 " .. M.fmt("g", d.th.g_hi) .. " ppm"
    end
    return string.format("阈值 %s - %s %s",
        M.fmt(key, d.th[key .. "_lo"]), M.fmt(key, d.th[key .. "_hi"]), M.UNIT[key])
end

-- 卡片用的紧凑阈值描述（卡片单格只有 88px 宽，必须省略前缀）
function M.th_range_short(d, key)
    if key == "g" then
        return "上限 " .. M.fmt("g", d.th.g_hi)
    end
    return string.format("%s - %s", M.fmt(key, d.th[key .. "_lo"]), M.fmt(key, d.th[key .. "_hi"]))
end

--------------------------------------------------------------------
-- 设备开关
--------------------------------------------------------------------
function M.toggle(d, key)
    if not d or d.dev[key] == nil then return false end
    d.dev[key] = not d.dev[key]
    return d.dev[key]
end

--------------------------------------------------------------------
-- 状态判定
--------------------------------------------------------------------
local TOL = conf.sim.tolerance

local function over(d, key)
    if key == "t" then
        return d.temp < d.th.t_lo - TOL or d.temp > d.th.t_hi + TOL
    elseif key == "h" then
        return d.hum < d.th.h_lo - TOL or d.hum > d.th.h_hi + TOL
    end
    return d.gas > d.th.g_hi + TOL
end

local function push_alarm(d, key)
    local v = (key == "t") and d.temp or (key == "h") and d.hum or d.gas
    local txt
    if key == "g" then
        txt = string.format("%s 有毒气体 %s ppm 超过上限 %s", d.name, M.fmt("g", v), M.fmt("g", d.th.g_hi))
    else
        local hi = (key == "t") and d.th.t_hi or d.th.h_hi
        local lo = (key == "t") and d.th.t_lo or d.th.h_lo
        local dir = (v > hi) and "高于上限" or "低于下限"
        txt = string.format("%s %s %s%s %s", d.name, M.NAME[key], M.fmt(key, v), M.UNIT[key], dir)
    end
    table.insert(S.alarms, 1, { time = os.date("%H:%M"), text = txt, id = d.id })
    while #S.alarms > 20 do table.remove(S.alarms) end
    log.warn("store", "报警", txt)
end

-- silent = true 时不产生报警日志（用于初始化/改阈值）
judge = function(d, silent)
    local old_t, old_h, old_g = d.st.t, d.st.h, d.st.g

    d.st.t = over(d, "t")
    d.st.h = over(d, "h")
    d.st.g = over(d, "g")
    d.st.any = d.st.t or d.st.h or d.st.g

    if not silent then
        if d.st.t and not old_t then push_alarm(d, "t") end
        if d.st.h and not old_h then push_alarm(d, "h") end
        if d.st.g and not old_g then push_alarm(d, "g") end
    end
end

function M.status(d) return d.st end

function M.any_alarm()
    for _, d in ipairs(S.devices) do
        if d.st.any then return true end
    end
    return false
end

function M.alarm_devices()
    local n = 0
    for _, d in ipairs(S.devices) do
        if d.st.any then n = n + 1 end
    end
    return n
end

function M.alarms() return S.alarms end

function M.last_alarm()
    return S.alarms[1]
end

--------------------------------------------------------------------
-- 初始化
--------------------------------------------------------------------
function M.init()
    local ok, t = pcall(os.time)
    math.randomseed(((ok and t) or 1000) % 100000 + 7)

    S.rooms = {}
    S.devices = {}
    S.alarms = {}
    S.tick = 0
    S.anomaly = nil
    S.next_id = 1
    S.next_rid = 1

    local r1 = M.add_room("宠物房")
    local r2 = M.add_room("客厅")
    local r3 = M.add_room("阳台")

    M.add_device("小米", "chick", r1.id)
    M.add_device("布丁", "cat", r1.id)
    M.add_device("团子", "rabbit", r2.id)
    M.add_device("芝麻", "hamster", r3.id)
end

--------------------------------------------------------------------
-- 模拟推进
--------------------------------------------------------------------
local function inject_anomaly()
    if S.anomaly then return end
    if #S.devices == 0 then return end
    local d = S.devices[math.random(#S.devices)]
    local pool = { "t", "h", "g" }
    local key = pool[math.random(3)]
    S.anomaly = { id = d.id, key = key, dir = (math.random(2) == 1) and 1 or -1, total = conf.sim.anomaly_ticks, done = 0 }
end

function M.tick()
    S.tick = S.tick + 1

    if S.anomaly then
        local an = S.anomaly
        an.done = an.done + 1
        local d = M.get(an.id)
        if an.done >= an.total or not d then S.anomaly = nil end
    elseif S.tick % conf.sim.anomaly_every == 0 then
        inject_anomaly()
    end

    for i, d in ipairs(S.devices) do
        local t_tgt = 28.0 + (i % 3) * 0.35
        local h_tgt = 56 - (i % 2) * 3
        local g_tgt = 1.1 + (i % 4) * 0.25

        if d.dev.warm then t_tgt = t_tgt + 3.4; h_tgt = h_tgt - 9 end
        if d.dev.cool then t_tgt = t_tgt - 3.2; h_tgt = h_tgt + 7 end
        if d.dev.light then g_tgt = g_tgt - 0.35 end

        -- 异常注入：正弦包络，平滑升起再回落
        local an = S.anomaly
        if an and an.id == d.id then
            local k = an.done / an.total
            if k > 1 then k = 1 end
            local env = math.sin(k * math.pi)
            if an.key == "t" then
                t_tgt = t_tgt + an.dir * 6.5 * env
            elseif an.key == "h" then
                h_tgt = h_tgt + an.dir * 26 * env
            else
                g_tgt = g_tgt + an.dir * 9.0 * env
            end
        end

        -- 自然波动
        local ph = i * 1.9
        t_tgt = t_tgt + math.sin(S.tick / 5.0 + ph) * 0.18
        h_tgt = h_tgt + math.sin(S.tick / 7.0 + ph) * 1.1
        g_tgt = g_tgt + math.sin(S.tick / 6.0 + ph) * 0.15
        if g_tgt < 0 then g_tgt = 0 end

        d.temp = d.temp + (t_tgt - d.temp) * 0.16 + rnd(-0.05, 0.05)
        d.hum  = d.hum + (h_tgt - d.hum) * 0.12 + rnd(-0.35, 0.35)
        d.gas  = d.gas + (g_tgt - d.gas) * 0.14 + rnd(-0.05, 0.05)

        if d.temp < 5 then d.temp = 5 elseif d.temp > 48 then d.temp = 48 end
        if d.hum < 5 then d.hum = 5 elseif d.hum > 95 then d.hum = 95 end
        if d.gas < 0 then d.gas = 0 elseif d.gas > 60 then d.gas = 60 end

        push_hist(d.hist.t, d.temp)
        push_hist(d.hist.h, d.hum)
        push_hist(d.hist.g, d.gas)

        judge(d, false)
    end
end

return M
