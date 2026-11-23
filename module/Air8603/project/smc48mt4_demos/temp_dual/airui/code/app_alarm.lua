--[[
@module  app_alarm
@summary 报警状态机（回差 + 确认延时）+ 最近 8 条记录 + 消音/复位
@version 1.0.0
@date    2026.11.16

状态：正常 / 预警 / 报警 / 断线
规则：
 1. 先判断线，再判温度——断线时温度是无效值，不能拿去比阈值，否则会同时
    冒出"断线"和"低温"两条互相矛盾的记录；
 2. 升档按门限，降档要先退回回差，防止在门限附近反复跳变；
 3. 状态变化需持续 conf.alarm.delay_s 秒才认账，滤掉瞬时毛刺；
 4. 消音只停声音，不改状态、不改颜色；新报警自动解除消音；
 5. 复位只清锁存，若此刻仍超限，下一轮判定会重新置位并再次发声；
 6. 记录只在状态变化时写，同一状态不重复记。
]]
local M = {}

local conf = require "conf"

local ST = { NORMAL = 0, WARN = 1, ALARM = 2, FAULT = 3 }
M.ST = ST

M.records = {}          -- 最新在前
M.mute = false
M.latched = false       -- 是否有未复位的报警

local ch = {}
for i = 1, #conf.chs do
    ch[i] = {
        state = ST.NORMAL,
        pending = ST.NORMAL,
        pend_at = 0,
    }
end

local listeners = {}

function M.on_update(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

local function notify(evt)
    for i = 1, #listeners do
        pcall(listeners[i], evt)
    end
end

local function push_record(chid, typ, value, limit)
    local rec = {
        t = os.time(),
        ch = chid,
        typ = typ,
        value = value,
        limit = limit,
    }
    table.insert(M.records, 1, rec)
    while #M.records > conf.alarm.max do
        table.remove(M.records)
    end
    notify("record")
end

-- 记录里描述通道的名字
function M.rec_label(rec)
    if rec.ch == 0 then return "系统" end
    local c = conf.chs[rec.ch]
    return c and c.key:upper() or ("CH" .. rec.ch)
end

function M.state_name(s)
    if s == ST.WARN then return "预警" end
    if s == ST.ALARM then return "报警" end
    if s == ST.FAULT then return "断线" end
    return "正常"
end

function M.state_of(i)
    return ch[i] and ch[i].state or ST.NORMAL
end

-- 带回差的分类
local function classify(v, cur, i)
    local c = conf.chs[i]
    local w, a, h = c.warn, c.alarm, conf.alarm.hysteresis
    if cur == ST.ALARM then
        if v >= a - h then return ST.ALARM end
        if v >= w - h then return ST.WARN end
        return ST.NORMAL
    elseif cur == ST.WARN then
        if v >= a then return ST.ALARM end
        if v >= w - h then return ST.WARN end
        return ST.NORMAL
    else
        if v >= a then return ST.ALARM end
        if v >= w then return ST.WARN end
        return ST.NORMAL
    end
end

--[[
判定一路
@param i number 通道号
@param v number 温度值（℃）
]]
function M.eval(i, v)
    local st = ch[i]
    if not st then return end
    local now = os.time()

    local want
    if v == nil or v <= conf.alarm.raw_fault then
        want = ST.FAULT
    else
        want = classify(v, st.state, i)
    end

    -- 断线是硬故障，立即生效，不排队等确认延时。
    -- 若走延时，输入间歇归零时永远凑不满 3 秒，界面会一直显示"正常"。
    if want == ST.FAULT and st.state ~= ST.FAULT then
        st.state = ST.FAULT
        st.pending = ST.FAULT
        st.pend_at = now
        push_record(i, "断线", nil, nil)
        M.latched = true
        M.mute = false
        notify("state")
        return
    end

    if want ~= st.state then
        if want ~= st.pending then
            st.pending = want
            st.pend_at = now
        elseif now - st.pend_at >= conf.alarm.delay_s then
            local from = st.state
            st.state = want
            st.pending = want

            if want == ST.ALARM then
                push_record(i, "报警", v, conf.chs[i].alarm)
                M.latched = true
                M.mute = false                  -- 新报警重新响
            elseif want == ST.FAULT then
                push_record(i, "断线", nil, nil)
                M.latched = true
                M.mute = false
            elseif want == ST.WARN then
                push_record(i, "预警", v, conf.chs[i].warn)
            elseif from == ST.ALARM or from == ST.FAULT then
                push_record(i, "恢复", v, nil)
            end

            notify("state")
        end
    else
        st.pending = st.state
    end
end

--[[
通讯状态变化
@param ok boolean 在线为 true
]]
function M.on_comm(ok)
    if ok then
        push_record(0, "通信恢复", nil, nil)
    else
        -- 通讯中断时两路都置断线，避免保留一个看似正常的旧值
        for i = 1, #conf.chs do
            if ch[i].state ~= ST.FAULT then
                ch[i].state = ST.FAULT
                ch[i].pending = ST.FAULT
            end
        end
        push_record(0, "通信中断", nil, nil)
        M.latched = true
        M.mute = false
        notify("state")
    end
end

-- 消音：只停声音
function M.mute_on()
    M.mute = true
    notify("mute")
end

-- 复位：清锁存；仍超限会在下一轮重新置位
function M.reset()
    M.latched = false
    M.mute = false
    for i = 1, #conf.chs do
        -- 状态保留（温度事实没变），只清"需人工确认"的标记
    end
    notify("reset")
end

-- 是否需要发声
function M.should_sound()
    if M.mute then return false end
    for i = 1, #conf.chs do
        if ch[i].state == ST.ALARM or ch[i].state == ST.FAULT then
            return true
        end
    end
    return false
end

-- 整体严重程度，供界面取色
function M.worst_state()
    local worst = ST.NORMAL
    for i = 1, #conf.chs do
        local s = ch[i].state
        if s == ST.FAULT then return ST.FAULT end
        if s == ST.ALARM then worst = ST.ALARM
        elseif s == ST.WARN and worst < ST.WARN then worst = ST.WARN end
    end
    return worst
end

function M.init()
    M.records = {}
    M.mute = false
    M.latched = false
end

return M
