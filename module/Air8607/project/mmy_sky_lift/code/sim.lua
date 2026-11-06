--[[
@module  sim
@summary SkyLift 运营模型：索道运力、客流排队、造雪与雪深、气象、设备、事件
@version 1.0
@date    2026.11.06
@note    全部数据本地演化，无外部传感器；接入实机时用 push() 覆盖即可
]]
local conf = require "conf"

local M = {}

local MIN_PER_TICK = conf.sim.min_per_tick
local HIST_MAX = conf.sim.history
local OPEN_MIN = 8 * 60          -- 雪场 08:00 开门
local CLOSE_MIN = 17 * 60        -- 17:00 停售

-- ===================== 工具 =====================
local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local rng = 20261106
local function rnd()
    rng = (rng * 1103515245 + 12345) % 2147483648
    return rng / 2147483648
end

local function rnd_range(lo, hi)
    return lo + (hi - lo) * rnd()
end

local function push_hist(name, v)
    local h = M.data.hist[name]
    if not h then return end
    h[#h + 1] = v
    if #h > HIST_MAX then table.remove(h, 1) end
end

-- 到客率（人/分钟）：早晚低、上午与午后双峰
local ARRIVAL = { [8] = 9, [9] = 25, [10] = 31, [11] = 27, [12] = 15,
                  [13] = 21, [14] = 26, [15] = 19, [16] = 9, [17] = 3 }

local function arrival_rate(minute_of_day)
    local h = math.floor(minute_of_day / 60) % 24
    local rate = ARRIVAL[h] or 2
    local frac = (minute_of_day % 60) / 60
    local next_rate = ARRIVAL[(h + 1) % 24] or 2
    return rate + (next_rate - rate) * frac
end

-- ===================== 时钟 / 光照 =====================
function M.clock()
    local m = (OPEN_MIN + M.data.t) % (24 * 60)
    return string.format("%02d:%02d", math.floor(m / 60), m % 60)
end

function M.minute_of_day()
    return (OPEN_MIN + M.data.t) % (24 * 60)
end

function M.daylight()
    local m = M.minute_of_day()
    local sunrise, sunset = 7 * 60 + 20, 17 * 60 + 40
    if m <= sunrise - 40 or m >= sunset + 40 then return 0.04 end
    if m < sunrise + 50 then
        return 0.04 + 0.96 * clamp((m - (sunrise - 40)) / 130, 0, 1)
    end
    if m > sunset - 60 then
        return 0.04 + 0.96 * clamp(((sunset + 40) - m) / 130, 0, 1)
    end
    return 1.0
end

function M.phase_text()
    local d = M.daylight()
    local m = M.minute_of_day()
    if d < 0.15 then return "夜间" end
    if m < 11 * 60 then return "上午" end
    if m < 14 * 60 then return "正午" end
    if m < 17 * 60 then return "午后" end
    return "黄昏"
end

-- ===================== 事件 =====================
local function push_event(text, level, strong)
    local ev = { text = text, level = level or "ok", clock = M.clock() }
    table.insert(M.data.events, 1, ev)
    if #M.data.events > 24 then table.remove(M.data.events) end
    if strong then M.data.last_event = ev end
    return ev
end
M.push_event = push_event

-- ===================== 初始化 =====================
local function init()
    local d = {
        t = 0,
        ticks = 0,
        paused = false,
        visitors = 0,          -- 今日运送人次
        queue = 0,             -- A 线站台排队人数
        wait_min = 0,          -- 预计等待
        lifts = {},
        slopes = {},
        guns = {},
        devices = {},
        health = {},
        events = {},
        hist = { speed = {}, queue = {}, depth = {}, wind = {}, tension = {}, current = {}, visitors = {} },
        event_cursor = 1,
        burst_until = -1,
        last_event = nil,
        groom_at = "06:10",
    }

    local cap = { a = 2400, b = 1200, c = 360 }
    for _, v in ipairs(conf.lifts) do
        d.lifts[v.key] = {
            key = v.key, name = v.name, type = v.type, short = v.short,
            cabins = v.cabins, seats = v.seats, length = v.length, towers = v.towers,
            bottom = v.bottom, top = v.top, color = v.color,
            max_speed = v.max_speed, target = v.speed, speed = v.speed,
            capacity_max = cap[v.key] or 600,
            capacity = 0, load = 0.6, riders = 0,
            state = "run", state_text = "运行中",
            tension = 240, current = 180,
        }
    end

    for _, v in ipairs(conf.slopes) do
        d.slopes[v.key] = {
            key = v.key, name = v.name, level = v.level, len = v.len, grad = v.grad,
            target = v.target, depth = v.target * 0.82, groom = v.groom,
            open = true, packed = false,
        }
    end

    for _, v in ipairs(conf.guns) do
        d.guns[v.key] = {
            key = v.key, name = v.name, sector = v.sector, x = v.x, rate = v.rate,
            on = (v.key ~= "g2"), nozzle = 70, output = 0, fault = false,
        }
    end

    for _, v in ipairs(conf.devices) do
        d.devices[v.key] = { key = v.key, name = v.name, icon = v.icon, note = v.note,
                             w = v.w, on = v.on }
    end

    for _, v in ipairs(conf.health) do
        d.health[v.key] = { key = v.key, name = v.name, unit = v.unit, dec = v.dec,
                            base = v.base, jitter = v.jitter, lo = v.lo, hi = v.hi,
                            dhi = v.dhi, dlo = v.dlo, value = v.base }
    end

    d.weather = {
        temp = conf.weather.base_temp,
        wind = conf.weather.base_wind,
        hum = conf.weather.base_hum,
        vis = conf.weather.base_vis,
        condition = "多云",
        wetbulb = -8.2,
        gust = 0,
    }

    d.cond = 0
    d.tension = 242
    d.current = 205
    d.wind_stop = false       -- 大风停运（带回差）
    d.wind_derate = false     -- 大风降速（带回差）

    M.data = d
    return d
end

-- ===================== 演化 =====================
local function weather_step(dt)
    local d = M.data
    local w = d.weather
    local h = (OPEN_MIN + d.t) / 60

    -- 气温：日变化 + 缓慢起伏
    local target = conf.weather.base_temp + 2.4 * math.sin((h - 9) / 24 * math.pi * 2)
    w.temp = w.temp + (target - w.temp) * 0.18 + (rnd() - 0.5) * 0.12

    -- 阵风：随机脉冲后衰减
    if w.gust > 0 then
        w.gust = math.max(0, w.gust - 0.35)
    elseif rnd() < 0.035 then
        w.gust = rnd_range(4, 9)
    end
    local wind_target = conf.weather.base_wind + w.gust + 1.6 * math.sin(d.t / 260)
    w.wind = clamp(w.wind + (wind_target - w.wind) * 0.25, 0.5, 26)

    -- 降雪：低温 + 高湿
    if w.temp < -3 and w.hum > 78 and rnd() < 0.02 then
        d.cond = 1
    elseif d.cond == 1 and rnd() < 0.03 then
        d.cond = 0
    end
    w.condition = (d.cond == 1) and "小雪" or (w.temp > 0 and "阴" or "多云")

    w.hum = clamp(w.hum + (rnd() - 0.5) * 2.2, 42, 96)
    local vis_base = (d.cond == 1) and 5.5 or 14
    w.vis = clamp(w.vis + (vis_base - w.vis) * 0.08 + (rnd() - 0.5) * 0.2, 1.2, 25)
    w.wetbulb = w.temp - (100 - w.hum) / 5
end

local function lift_step(dt)
    local d = M.data
    local w = d.weather

    -- 风速保护加 1.5 m/s 回差（滞环）。没有回差时风速在阈值上下抖动，
    -- 目标速度就会在 2.6 与 5.0 之间反复横跳，趋势曲线被切成一段段平台，像方波。
    local stop_line, warn_line = conf.weather.wind_stop, conf.weather.wind_warn
    if w.wind >= stop_line then
        d.wind_stop = true
    elseif w.wind < stop_line - 1.5 then
        d.wind_stop = false
    end
    if w.wind >= warn_line then
        d.wind_derate = true
    elseif w.wind < warn_line - 1.5 then
        d.wind_derate = false
    end

    for _, key in ipairs({ "a", "b", "c" }) do
        local l = d.lifts[key]
        local main_on = d.devices.drive.on
        local goal = l.target

        -- 风速保护
        if d.wind_stop then
            goal = 0
            l.state, l.state_text = "stop", "大风停运"
        elseif d.wind_derate then
            goal = math.min(goal, 2.6)
            l.state, l.state_text = "derate", "降速运行"
        elseif not main_on then
            goal = 0
            l.state, l.state_text = "stop", "驱动停机"
        else
            l.state, l.state_text = "run", "运行中"
        end

        if key == "c" then
            -- 魔毯不受风影响
            goal = main_on and l.target or 0
            if main_on then l.state, l.state_text = "run", "运行中" end
        end

        -- 一阶惯性逼近目标速度：系数小一点，加减速才是缓坡而不是台阶
        l.speed = l.speed + (goal - l.speed) * 0.18
        if math.abs(l.speed - goal) < 0.02 then l.speed = goal end

        local ratio = (l.speed > 0) and (l.speed / l.max_speed) or 0
        l.load = clamp(0.55 + d.queue / 260, 0.45, 1)
        l.capacity = math.floor(l.capacity_max * ratio * l.load)
        l.riders = l.riders + math.floor(l.capacity * dt / 60)

        -- 钢绳张力 / 电机电流（用于曲线）
        -- 摆动幅度按真实钢绳张力波动给（±6.5 kN 慢摆 + 采样噪声），曲线才有起伏
        l.tension = 235 + ratio * 38 + math.sin(d.t / 9) * 6.5 + (rnd() - 0.5) * 2.5
        l.current = 90 + ratio * 240 + (rnd() - 0.5) * 6
        if key == "a" then
            d.tension = l.tension
            d.current = l.current
        end
    end
end

local function queue_step(dt)
    local d = M.data
    local m = M.minute_of_day()
    local rate = arrival_rate(m)
    if m >= CLOSE_MIN or m < OPEN_MIN then rate = rate * 0.15 end

    local arrive = rate * dt
    local served = 0
    for _, key in ipairs({ "a", "b", "c" }) do
        served = served + d.lifts[key].capacity * dt / 60
    end

    d.queue = clamp(d.queue + arrive - served, 0, 900)
    d.visitors = d.visitors + served
    d.wait_min = math.floor(d.queue / math.max(4, served / dt))
end

local function snow_step(dt)
    local d = M.data
    local w = d.weather
    local wet = w.wetbulb
    local can_make = (wet <= -2)

    for _, g in pairs(d.guns) do
        if g.on and not g.fault and can_make then
            g.output = g.rate * (g.nozzle / 100)
        else
            g.output = 0
        end
    end

    for _, s in pairs(d.slopes) do
        local gain = 0
        for _, g in pairs(d.guns) do
            if g.on and g.output > 0 and g.sector == s.name then
                gain = gain + g.output * 0.1 * (dt / 60) * 6
            end
        end
        -- 天然降雪
        if d.cond == 1 then gain = gain + 1.1 * (dt / 60) end
        -- 融雪
        local melt = 0
        if w.temp > 0 then
            melt = 0.30 * (dt / 60) * (1 + (w.temp / 6))
        elseif d.burst_until > d.t then
            gain = gain + 2.0 * (dt / 60)
        end
        s.depth = clamp(s.depth + gain - melt, 0, 180)
        s.open = s.depth >= s.target * 0.55
    end
end

local function health_step(dt)
    local d = M.data
    local speed = d.lifts.a.speed
    for _, v in ipairs(conf.health) do
        local h = d.health[v.key]
        local base = v.base
        if v.key == "mtemp" then base = v.base + speed * 2.2 end
        if v.key == "rope" then base = v.base + (d.tension - 242) * 0.6 end
        if v.key == "hydro" then base = v.base + speed * 0.9 end
        h.value = h.value + (base - h.value) * 0.08 + (rnd() - 0.5) * v.jitter
    end
end

local function timeline_step()
    local d = M.data
    local ev = conf.events[d.event_cursor]
    if ev and d.ticks >= ev.after then
        d.event_cursor = d.event_cursor + 1
        if ev.gun then
            local g = d.guns[ev.gun]
            if g then g.on = false; g.fault = true end
        end
        if ev.groom then
            M.groom(true)
        end
        push_event(ev.text, ev.level, true)
    end
end

function M.tick()
    local d = M.data
    d.ticks = d.ticks + 1
    if not d.paused then
        local dt = MIN_PER_TICK
        d.t = d.t + dt
        weather_step(dt)
        lift_step(dt)
        queue_step(dt)
        snow_step(dt)
        health_step(dt)
        timeline_step()

        local depth_sum, depth_n = 0, 0
        for _, s in pairs(d.slopes) do
            depth_sum = depth_sum + s.depth
            depth_n = depth_n + 1
        end

        -- 趋势采样叠加真实工况波动（载荷、电网扰动带来的转速摆动）。
        -- 恒速段的 l.speed 是常数，直接入库的话曲线就是一条直线。
        local sp_wobble = 1 + math.sin(d.t / 4.3) * 0.10 + (rnd() - 0.5) * 0.03
        push_hist("speed", d.lifts.a.speed * sp_wobble)
        push_hist("queue", d.queue)
        push_hist("depth", depth_sum / math.max(1, depth_n))
        push_hist("wind", d.weather.wind)
        push_hist("tension", d.tension)
        push_hist("current", d.current)
        push_hist("visitors", d.visitors)
    end
    local ev = d.last_event
    d.last_event = nil
    return ev
end

-- ===================== 读取 =====================
function M.lift(key)
    return M.data.lifts[key]
end

function M.slope(key)
    return M.data.slopes[key]
end

function M.gun(key)
    return M.data.guns[key]
end

function M.device(key)
    return M.data.devices[key]
end

function M.health(key)
    return M.data.health[key]
end

function M.weather()
    return M.data.weather
end

function M.history(name)
    return M.data.hist[name] or {}
end

function M.events(n)
    local out = {}
    for i = 1, math.min(n or 7, #M.data.events) do
        out[i] = M.data.events[i]
    end
    return out
end

function M.speed()
    return M.data.lifts.a.speed
end

function M.target(key)
    return (M.data.lifts[key or "a"] or {}).target or 0
end

function M.online_cars()
    local n = 0
    for _, key in ipairs({ "a", "b", "c" }) do
        local l = M.data.lifts[key]
        if l.speed > 0.1 then n = n + l.cabins end
    end
    return n
end

function M.capacity_now()
    local n = 0
    for _, key in ipairs({ "a", "b", "c" }) do
        n = n + M.data.lifts[key].capacity
    end
    return n
end

function M.avg_depth()
    local sum, n = 0, 0
    for _, s in pairs(M.data.slopes) do
        sum = sum + s.depth
        n = n + 1
    end
    return sum / math.max(1, n)
end

function M.slopes()
    local out = {}
    for _, v in ipairs(conf.slopes) do out[#out + 1] = M.data.slopes[v.key] end
    return out
end

function M.guns()
    local out = {}
    for _, v in ipairs(conf.guns) do out[#out + 1] = M.data.guns[v.key] end
    return out
end

function M.devices()
    local out = {}
    for _, v in ipairs(conf.devices) do out[#out + 1] = M.data.devices[v.key] end
    return out
end

function M.health_list()
    local out = {}
    for _, v in ipairs(conf.health) do out[#out + 1] = M.data.health[v.key] end
    return out
end

function M.open_slopes()
    local open, total = 0, 0
    for _, s in pairs(M.data.slopes) do
        total = total + 1
        if s.open then open = open + 1 end
    end
    return open, total
end

function M.gun_output()
    local out = 0
    for _, g in pairs(M.data.guns) do out = out + g.output end
    return out
end

function M.feels_like()
    local w = M.data.weather
    return w.temp - w.wind * 0.42
end

function M.risk()
    local w = M.data.weather
    if w.wind >= conf.weather.wind_stop then
        return "danger", "风速超限 · 索道停运"
    elseif w.wind >= conf.weather.wind_warn then
        return "warn", "阵风偏大 · 已自动降速"
    elseif w.vis < 3 then
        return "warn", "能见度低 · 建议减速"
    elseif w.temp > 2 then
        return "warn", "气温回升 · 雪面融化"
    end
    return "ok", "气象条件良好"
end

-- 全站健康等级（取最差一项）
function M.health_worst()
    local level, worst = "ok", nil
    for _, v in ipairs(conf.health) do
        local h = M.data.health[v.key]
        local lv = "ok"
        if (v.dhi and h.value > v.dhi) or (v.dlo and h.value < v.dlo) then
            lv = "danger"
        elseif h.value > v.hi or h.value < v.lo then
            lv = "warn"
        end
        if lv == "danger" then return "danger", h end
        if lv == "warn" then level, worst = "warn", h end
    end
    return level, worst
end

function M.summary()
    local d = M.data
    local depth = M.avg_depth()
    return {
        clock = M.clock(),
        phase = M.phase_text(),
        speed = d.lifts.a.speed,
        capacity = M.capacity_now(),
        depth = depth,
        cars = M.online_cars(),
        -- 计数类字段对外一律取整：UI 里 string.format("%d", x) 不接受浮点
        queue = math.floor(d.queue + 0.5),
        wait = math.floor(d.wait_min),
        visitors = math.floor(d.visitors + 0.5),
        temp = d.weather.temp,
        wind = d.weather.wind,
        hum = d.weather.hum,
        vis = d.weather.vis,
        cond = d.weather.condition,
        wetbulb = d.weather.wetbulb,
        feels = M.feels_like(),
        driving = math.floor(d.lifts.a.capacity / 4),
        open_slopes = select(1, M.open_slopes()),
        total_slopes = select(2, M.open_slopes()),
        paused = d.paused,
    }
end

-- ===================== 控制 =====================
function M.set_target(key, v)
    local l = M.data.lifts[key or "a"]
    if not l then return end
    l.target = clamp(v, 0, l.max_speed)
end

function M.toggle_pause()
    M.data.paused = not M.data.paused
    push_event(M.data.paused and "演示模型已暂停" or "演示模型已恢复", "ok")
    return M.data.paused
end

function M.is_paused()
    return M.data.paused
end

function M.toggle_device(key)
    local dev = M.data.devices[key]
    if not dev then return end
    dev.on = not dev.on

    if key == "drive" then
        local l = M.data.lifts.a
        l.state, l.state_text = dev.on and "run" or "stop", dev.on and "运行中" or "驱动停机"
        push_event(dev.on and "主驱动已启动，索道恢复运行" or "主驱动已停机，索道停止运行",
            dev.on and "ok" or "warn", true)
    elseif key == "gun" then
        for _, g in pairs(M.data.guns) do
            g.on = dev.on and not g.fault
        end
        push_event(dev.on and "造雪系统已开启" or "造雪系统已关闭", "ok", true)
    elseif key == "backup" then
        push_event(dev.on and "备用电机已切入，等待带载" or "备用电机已退出", dev.on and "warn" or "ok", true)
    elseif key == "light" then
        push_event(dev.on and "沿线照明已开启" or "沿线照明已关闭", "ok")
    elseif key == "heater" then
        push_event(dev.on and "除冰加热已开启" or "除冰加热已关闭", "ok")
    elseif key == "speaker" then
        push_event(dev.on and "广播系统已开启" or "广播系统已静音", "ok")
    end
    return dev.on
end

function M.toggle_gun(key)
    local g = M.data.guns[key]
    if not g then return end
    if g.fault then
        g.fault = false
        g.on = true
        push_event(g.name .. " 复位成功，恢复造雪", "ok", true)
        return g.on
    end
    g.on = not g.on
    push_event(g.name .. (g.on and " 启动造雪" or " 停止造雪"), "ok")
    return g.on
end

function M.set_nozzle(key, v)
    local g = M.data.guns[key]
    if not g then return end
    g.nozzle = clamp(math.floor(v), 0, 100)
end

-- 一键压雪
function M.groom(silent)
    local now = M.clock()
    for _, s in pairs(M.data.slopes) do
        if s.groom ~= "不压雪" then
            s.depth = math.max(s.depth, s.target * 0.96)
            s.packed = true
        end
    end
    M.data.groom_at = now
    if not silent then
        push_event("压雪作业完成，雪面已平整", "ok", true)
    end
end

-- 人工降雪（短时强化）
function M.burst()
    M.data.burst_until = M.data.t + 120
    push_event("启动人工降雪，预计持续 2 小时", "ok", true)
end

function M.reset()
    rng = 20261106
    init()
    push_event("演示数据已重置", "ok", true)
end

function M.uptime()
    return M.data.ticks * MIN_PER_TICK
end

-- 接入实机传感器时的写入口（无外设时仅供演示/调试）
function M.push(key, v)
    local d = M.data
    if key == "temp" then d.weather.temp = v
    elseif key == "wind" then d.weather.wind = v
    elseif key == "hum" then d.weather.hum = v
    elseif key == "vis" then d.weather.vis = v
    elseif key == "queue" then d.queue = v
    elseif key == "speed" then d.lifts.a.speed = v
    end
end

init()

return M

