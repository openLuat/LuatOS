--[[
@module  app_alarm
@summary 报警状态机 + 最近 8 条报警记录 + 消音/复位
@version 1.0.0
@date    2026.11.09

状态机（每通道独立）：
    NORMAL(0) --val>=warn--> WARN(1) --val>=alarm--> ALARM(2)
    降级必须满足回差：val < 阈值 - hysteresis，避免数值在阈值附近抖动刷屏。

规则：
- 只在"状态变化"时产生记录，同一状态持续不会重复刷记录；
- 新报警自动解除静音（保证不会漏掉新事件）；
- 消音只停声，不清除报警显示；
- 报警复位 = 全部标记已确认 + 静音；报警条件仍存在时状态保持，恢复后自动归档；
- 记录最多 8 条（需求），掉电保存到 fskv。
]]
local M = {}

local conf = require "conf"
local store = require "app_store"

M.state = {}          -- 每通道当前等级 0/1/2
M.recs = {}           -- 报警记录，最新在第 1 条
M.muted = false       -- 是否已消音
M.seq = 0             -- 记录自增 id

local listeners = {}

--[[
注册报警事件回调
@param fn function 回调，参数为事件名："new" / "recover" / "mute" / "ack" / "clear"
@return nil
]]
function M.on_change(fn)
    if type(fn) == "function" then
        listeners[#listeners + 1] = fn
    end
end

local function notify(evt)
    for i = 1, #listeners do
        pcall(listeners[i], evt)
    end
end

local function add_record(idx, level, val)
    local ch = conf.chs[idx]
    local rec = {
        id    = M.seq + 1,
        t     = os.time(),
        ch    = idx,
        name  = ch.name,
        level = level,                                  -- 1=预警 2=报警
        val   = tonumber(string.format("%.1f", val)) or val,
        thr   = (level == 2) and ch.alarm or ch.warn,
        acked = false,
    }
    M.seq = rec.id

    table.insert(M.recs, 1, rec)
    while #M.recs > conf.alarm.max do
        table.remove(M.recs)
    end

    M.muted = false  -- 新报警解除静音
    store.save_alarms(M.recs)
    log.warn("app_alarm", ch.name, level == 2 and "报警" or "预警", rec.val, "阈值", rec.thr)
    notify("new")
end

--[[
对一个通道的一次采样做报警判定
@param idx number 通道序号（1 起）
@param val number 换算后的工程量
@return nil
]]
function M.eval(idx, val)
    local ch = conf.chs[idx]
    if not ch then
        return
    end

    local st = M.state[idx] or 0
    local new

    if val >= ch.alarm then
        new = 2
    elseif val >= ch.warn then
        new = 1
    else
        new = 0
    end

    -- 回差：降级必须低于 阈值 - hysteresis
    if new < st then
        local h = conf.alarm.hysteresis
        if st == 2 and val >= ch.alarm - h then
            new = 2                       -- 仍在报警带内，保持报警
        elseif st >= 1 and new == 0 and val >= ch.warn - h then
            new = 1                       -- 仍在预警带内，降到预警
        end
    end

    if new ~= st then
        M.state[idx] = new
        if new > 0 then
            add_record(idx, new, val)
        else
            notify("recover")
        end
    end
end

--[[
当前最高报警等级
@return number 0=正常 1=预警 2=报警
]]
function M.max_level()
    local lv = 0
    for i = 1, #conf.chs do
        if (M.state[i] or 0) > lv then
            lv = M.state[i]
        end
    end
    return lv
end

--[[
消音：停止声音提示，不清除报警状态和弹窗
@return nil
]]
function M.mute()
    M.muted = true
    notify("mute")
end

--[[
报警复位：所有记录标记已确认 + 静音；条件恢复后自动归档
@return nil
]]
function M.ack()
    for _, r in ipairs(M.recs) do
        r.acked = true
    end
    M.muted = true
    store.save_alarms(M.recs)
    notify("ack")
end

--[[
清空报警记录（不影响当前报警状态）
@return nil
]]
function M.clear()
    M.recs = {}
    store.save_alarms(M.recs)
    notify("clear")
end

--[[
从 fskv 恢复历史报警记录，状态机归零
@return nil
]]
function M.init()
    for i = 1, #conf.chs do
        M.state[i] = 0
    end
    local saved = store.load_alarms()
    M.recs = saved or {}
    for _, r in ipairs(M.recs) do
        if (r.id or 0) > M.seq then
            M.seq = r.id
        end
    end
    log.info("app_alarm", "载入历史报警记录", #M.recs, "条")
end

return M
