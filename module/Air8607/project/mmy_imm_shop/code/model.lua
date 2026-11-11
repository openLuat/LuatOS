--[[
@module  model
@summary 注塑车间数据模型与工艺仿真（8 台机 / 成型周期 / 工艺实测 / 报警 / 产量）
@version 1.0
@date    2026.11.10

真实项目里把 M.tick() 里生成实测值的部分换成 Modbus/EUROMAP 采集即可，
上层 UI 只读 M.list() / M.actual() / M.stats()，不关心数据从哪来。
]]
local conf  = require("conf")
local store = require("store")

local M = {}

local machines = {}
M.sel = 1          -- 当前选中机台（工艺页）
M.t = 0
M.dirty = false    -- 有产出（UI 可用它决定是否重绘）

-- ==================== 内部工具 ====================
local function recipe() return store.params() end

-- 由工艺参数推导成型周期（秒），并限制在机型区间内
local function calc_cycle(p)
    local c = 6.0 + (p.hold_time or 3.2) + (p.cool_time or 16.5)
        + (p.inj_press or 88) / 100 * 4.0
        + (p.inj_speed or 62) / 100 * 3.0
    if c < conf.machine.cycle.min then c = conf.machine.cycle.min end
    if c > conf.machine.cycle.max then c = conf.machine.cycle.max end
    return c
end

local function find_mold(id)
    for _, m in ipairs(conf.molds) do
        if m.id == id then return m end
    end
end

local function add_alarm(m, code)
    local rec = {
        t = os.date("%H:%M:%S"),
        m = m.id,
        code = code.code,
        name = code.name,
        level = code.level,
        ack = false,
    }
    store.add_alarm(rec)
    m.alarm = rec
    m.state = "alarm"
    m.alarm_left = 18 + math.random(0, 25)   -- 秒后自动复位（模拟现场处理）
    log.warn("model", m.id .. " " .. code.code .. " " .. code.name)
end

-- ==================== 初始化 ====================
function M.init()
    math.randomseed(mcu.ticks() & 0x7FFFFFFF)
    machines = {}
    local p = recipe()

    for i = 1, conf.machine.count do
        local m = {
            idx = i,
            id = conf.machine_ids[i],
            cycle = calc_cycle(p),
            last_cycle = calc_cycle(p),
            t_cyc = math.random() * 10,
            shots = 0, ok = 0, ng = 0,
            hist = {},
            oil_t = 43 + math.random() * 5,
            good = 99.0 + math.random() * 0.8,
            state = "run",
            mold_acc = 0,
            alarm = nil,
        }
        for _, o in ipairs(conf.orders) do
            if o.machine == i then
                m.order, m.mold, m.product = o.id, o.mold, o.product
                m.plan, m.done = o.plan, o.done
            end
        end
        local md = m.mold and find_mold(m.mold)
        m.cavity = md and md.cavity or 2

        if i == 7 then                       -- 换模调机
            m.state, m.order, m.mold = "setup", "WO-2603-017", "M-107"
            m.product, m.plan, m.done = "装饰圈", 6000, 0
            m.cavity = 2
        elseif i == 8 then                   -- 停机保养
            m.state, m.order, m.mold = "stop", nil, "M-108"
            m.product, m.plan, m.done = "端盖", 9000, 0
            m.cavity = 6
        end

        -- 预热历史周期，让曲线一上电就有形
        for k = 1, 24 do
            m.hist[k] = m.cycle + (math.random() - 0.5) * 0.9
        end
        machines[i] = m
    end
    log.info("model", "机台模型初始化完成", #machines)
end

function M.list() return machines end
function M.get(i) return machines[i] end
function M.select(i) M.sel = i end
function M.current() return machines[M.sel] end

-- ==================== 仿真推进（1Hz）====================
-- 返回 true 表示本轮有新产出（UI 可据此刷新产量类文本）
function M.tick(dt)
    dt = dt or 1
    M.t = M.t + dt
    local p = recipe()
    local changed = false

    for _, m in ipairs(machines) do
        if m.state == "alarm" then
            m.alarm_left = (m.alarm_left or 0) - dt
            if m.alarm_left <= 0 then
                m.state = "run"
                m.alarm = nil
                log.info("model", m.id .. " 报警复位")
            end

        elseif m.state == "run" then
            m.t_cyc = m.t_cyc + dt
            if m.t_cyc >= m.cycle then
                m.t_cyc = m.t_cyc - m.cycle
                m.shots = m.shots + 1
                m.done = m.done + 1
                m.last_cycle = m.cycle

                table.insert(m.hist, m.cycle)
                if #m.hist > 30 then table.remove(m.hist, 1) end

                local ng = (math.random() < 0.012) and 1 or 0
                m.ok = m.ok + 1 - ng
                m.ng = m.ng + ng
                store.add_output(1 - ng, ng)

                -- 模具磨损（万模次），攒到 flush 再落盘
                m.mold_acc = m.mold_acc + m.cavity / 10000

                m.cycle = calc_cycle(p) + (math.random() - 0.5) * 0.8
                changed = true
            end

            -- 温度/压力越限与随机故障（每模开头判定一次）
            if m.t_cyc < 1.5 then
                local lim = store.settings()
                if m.oil_t > lim.oil_hi then
                    add_alarm(m, conf.alarm_codes[3])          -- 液压油温高
                elseif math.random() < 0.0012 then
                    local k = ({ 1, 2, 4, 5, 6, 7, 8 })[math.random(1, 7)]
                    add_alarm(m, conf.alarm_codes[k])
                end
            end
        end

        -- 液压油温向环境温度回落 / 随负载上升
        local target = (m.state == "run") and 48 or 40
        m.oil_t = m.oil_t + (target - m.oil_t) * 0.05 + (math.random() - 0.5) * 0.25
    end

    M.dirty = changed
    return changed
end

-- 模具模次批量落盘（由 main 每 60s 调）
function M.flush_molds()
    for _, m in ipairs(machines) do
        if m.mold_acc and m.mold_acc > 0 then
            store.add_mold_cycles(m.mold, m.mold_acc)
            m.mold_acc = 0
        end
    end
end

-- ==================== 派生数据 ====================
-- 当前成型阶段：返回 阶段下标, 阶段内进度(0~1)
function M.phase_of(m)
    if m.state ~= "run" then return 0, 0 end
    local pos = m.t_cyc / m.cycle
    local acc = 0
    for i, ph in ipairs(conf.phases) do
        if pos < acc + ph.ratio then
            return i, (pos - acc) / ph.ratio
        end
        acc = acc + ph.ratio
    end
    return #conf.phases, 1
end

-- 实测值（围绕设定值波动，模温随阶段略升）
function M.actual(m, key)
    local p = recipe()
    local set = p[key] or 0
    local w = M.t * 0.7 + m.idx
    local phase = M.phase_of(m)

    if key == "inj_press" then
        local base = (phase == 2 or phase == 3) and 1 or 0.25
        return set * (0.42 + base * 0.58) + math.sin(w) * 1.1
    elseif key == "inj_speed" then
        return set * ((phase == 2) and 1 or 0.15) + math.sin(w * 1.3) * 1.8
    elseif key == "hold_press" then
        return set * ((phase == 3) and 1 or 0.2) + math.sin(w * 0.9) * 0.7
    elseif key == "hold_time" then
        return set + math.sin(w * 0.5) * 0.04
    elseif key == "cool_time" then
        return set + math.sin(w * 0.4) * 0.08
    elseif key == "barrel_t" then
        return set + math.sin(w * 0.6) * 1.8 + (m.idx % 3) * 0.4
    elseif key == "mold_t" then
        local boost = (phase == 2 or phase == 3) and 1.6 or 0
        return set + boost + math.sin(w * 0.35) * 0.9
    elseif key == "back_press" then
        return set + math.sin(w * 1.1) * 0.3
    end
    return set
end

-- 总览 KPI
function M.stats()
    local s = { run = 0, idle = 0, alarm = 0, stop = 0, setup = 0,
                avg_cycle = 0, n_cycle = 0 }
    for _, m in ipairs(machines) do
        s[m.state] = (s[m.state] or 0) + 1
        if m.state == "run" then
            s.avg_cycle = s.avg_cycle + m.cycle
            s.n_cycle = s.n_cycle + 1
        end
    end
    if s.n_cycle > 0 then
        s.avg_cycle = s.avg_cycle / s.n_cycle
    end
    -- 今日产量以 store 记录为准（已在每模完成时累加）
    local t = store.today()
    s.today_ok = t.ok
    s.today_ng = t.ng
    s.yield = (t.ok + t.ng) > 0 and (t.ok / (t.ok + t.ng) * 100) or 100
    s.oee = #machines > 0 and (s.run / #machines * 100) or 0
    return s
end

return M
