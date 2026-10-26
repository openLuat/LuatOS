--[[
@module  line_sim
@summary 产线数据源（虚拟）：工位状态机 + 产量累计 + 异常生命周期 + 统计
@author  王世豪
@version 1.0
@date    2026.10.26
@usage
对外接口：
1、line_sim.init()                初始化 8 个工位与产线统计
2、line_sim.tick(dt)              每秒推进：产量、停机、异常升级、虚拟注入
3、line_sim.call_alarm(idx, key)  工位呼叫异常
4、line_sim.ack_alarm(idx, by)    班组长响应
5、line_sim.recover(idx)          恢复生产（记入停机统计）
6、line_sim.stations() / active_alarms() / stats() / count_by_state()
@note
这是"虚拟产线"，无外设也能完整演示。
接真机时：把 call_alarm 换成 GPIO 按钮中断回调，
把产量/节拍换成 RS485(Modbus) 读 PLC，界面层完全不用改。
]]
local conf = require "conf"

local M = {}

local S = {}         -- 工位状态数组
local line = {}      -- 产线级统计
local active = {}    -- 活动异常列表
local next_alarm_at = 0

local function type_name(key)
    for _, t in ipairs(conf.alarm_types) do
        if t.key == key then
            return t.name
        end
    end
    return key
end

function M.init()
    S = {}
    for i, st in ipairs(conf.stations) do
        S[i] = {
            idx = i,
            id = st.id,
            name = st.name,
            state = "run",      -- run / idle / alarm / changeover
            produced = 0,
            good = 0,
            acc = 0,            -- 产量小数累加器
            down_sec = 0,
            alarm = nil,
        }
    end
    line = {
        start_ts = os.time(),
        plan_sec = 0,
        run_sec = 0,
        down_sec = 0,
        produced = 0,
        good = 0,
        alarms_total = 0,
        response_samples = {},  -- 每次异常结束时的响应/等待时长（秒）
        by_type = {},
    }
    active = {}
    next_alarm_at = os.time() + math.random(8, 16)
    log.info("line", "虚拟产线已初始化", conf.line.name, "工位数", #S)
end

function M.state_text(st)
    if st.state == "run" then return "运行" end
    if st.state == "idle" then return "待机" end
    if st.state == "changeover" then return "换型" end
    if st.state == "alarm" then return "异常" end
    return "未知"
end

-- ==================== 异常生命周期 ====================
function M.call_alarm(idx, type_key, by)
    local st = S[idx]
    if not st or st.state == "alarm" then return false end
    local a = {
        station = idx,
        type = type_key,
        name = type_name(type_key),
        start = os.time(),
        ack = nil,
        ack_by = nil,
        level = 1,      -- 1 正常 / 2 超 warn / 3 超 timeout
    }
    st.state = "alarm"
    st.alarm = a
    active[#active + 1] = a
    log.info("line", "异常呼叫", st.name, a.name, "呼叫人", tostring(by or "操作工"))
    return true
end

function M.ack_alarm(idx, by)
    local st = S[idx]
    if not st or not st.alarm or st.alarm.ack then return false end
    st.alarm.ack = os.time()
    st.alarm.ack_by = by or "班组长"
    log.info("line", "异常已响应", st.name, st.alarm.name,
        "响应耗时", st.alarm.ack - st.alarm.start, "秒")
    return true
end

function M.recover(idx)
    local st = S[idx]
    if not st or st.state ~= "alarm" then return false end
    local a = st.alarm
    if a then
        a.end_ts = os.time()
        line.alarms_total = line.alarms_total + 1
        line.by_type[a.type] = (line.by_type[a.type] or 0) + (a.end_ts - a.start)
        local resp = (a.ack and a.ack or a.end_ts) - a.start
        line.response_samples[#line.response_samples + 1] = resp
        for i = #active, 1, -1 do
            if active[i] == a then table.remove(active, i) end
        end
    end
    st.state = "run"
    st.alarm = nil
    log.info("line", "恢复生产", st.name)
    return true
end

function M.set_changeover(idx)
    local st = S[idx]
    if not st or st.state == "alarm" then return false end
    st.state = "changeover"
    return true
end

function M.resume(idx)
    local st = S[idx]
    if not st or st.state == "alarm" then return false end
    st.state = "run"
    return true
end

-- ==================== 每秒推进 ====================
function M.tick(dt)
    dt = dt or 1
    line.plan_sec = line.plan_sec + dt

    local running = 0
    local now = os.time()

    for i, st in ipairs(S) do
        if st.state == "run" then
            running = running + 1
            st.acc = st.acc + dt / conf.line.cycle_time
            local n = math.floor(st.acc)
            if n > 0 then
                st.acc = st.acc - n
                st.produced = st.produced + n
                line.produced = line.produced + n
                for _ = 1, n do
                    if math.random() > 0.02 then   -- 98% 良品
                        st.good = st.good + 1
                        line.good = line.good + 1
                    end
                end
            end
        end

        if st.state == "alarm" and st.alarm then
            st.down_sec = st.down_sec + dt
            line.down_sec = line.down_sec + dt
            local wait = now - st.alarm.start
            if wait >= conf.threshold.ack_timeout then
                st.alarm.level = 3
            elseif wait >= conf.threshold.ack_warn then
                st.alarm.level = 2
            end
            if conf.sim.auto_recover and wait >= 45 then
                M.recover(i)
            end
        end
    end

    if running > 0 then
        line.run_sec = line.run_sec + dt
    end

    -- 虚拟异常注入（纯演示，接真机时删掉这段）
    if conf.sim.enabled and now >= next_alarm_at then
        local cand = {}
        for i, st in ipairs(S) do
            if st.state == "run" then cand[#cand + 1] = i end
        end
        if #cand > 0 then
            local idx = cand[math.random(#cand)]
            local tp = conf.alarm_types[math.random(#conf.alarm_types)]
            M.call_alarm(idx, tp.key, "操作工")
        end
        next_alarm_at = now + math.random(conf.sim.alarm_min, conf.sim.alarm_max)
    end
end

-- ==================== 查询 ====================
function M.stations() return S end
function M.active_alarms() return active end

function M.stats()
    local rs = line.response_samples
    local sum, mx = 0, 0
    for _, v in ipairs(rs) do
        sum = sum + v
        if v > mx then mx = v end
    end
    return {
        plan_sec = line.plan_sec,
        run_sec = line.run_sec,
        down_sec = line.down_sec,
        produced = line.produced,
        good = line.good,
        alarms_total = line.alarms_total,
        by_type = line.by_type,
        avg_response = (#rs > 0) and (sum / #rs) or 0,
        max_response = mx,
    }
end

function M.count_by_state()
    local n = { run = 0, idle = 0, changeover = 0, alarm = 0 }
    for _, st in ipairs(S) do
        n[st.state] = (n[st.state] or 0) + 1
    end
    return n
end

return M
