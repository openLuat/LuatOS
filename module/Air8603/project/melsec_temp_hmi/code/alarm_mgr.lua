--[[
@module  alarm
@summary 报警状态机：预警/报警/回差/最近 8 条记录/消音/复位
         温度单位统一用 0.1℃ 整数
]]

local M = {}

local cfg = require("config")
local MAX = 8

local level = { 0, 0 }        -- 0=正常 1=预警 2=报警
local records = {}            -- 最新的在前
local muted = false
local seq = 0
local listeners = {}

local function now_str()
    return os.date("%H:%M:%S")
end

-- 带回差的判定：回落要低于阈值 1.0℃ 才降级，避免阈值附近抖动刷屏
local function judge(v, warn, alarm, lv)
    if v >= alarm then return 2 end
    if lv == 2 and v > alarm - cfg.hyst then return 2 end
    if v >= warn then return 1 end
    if lv == 1 and v > warn - cfg.hyst then return 1 end
    return 0
end

local function fire(evt, rec)
    for _, fn in ipairs(listeners) do
        pcall(fn, evt, rec)
    end
end

local function add_record(i, lv, value)
    seq = seq + 1
    table.insert(records, 1, {
        id = seq,
        time = now_str(),
        ch = i,
        level = lv,
        value = value,
        acked = false,
        resolved = false,
    })
    while #records > MAX do table.remove(records) end
    if muted then muted = false end        -- 新报警自动解除消音
    fire("new", records[1])
end

-- temps[i] 为 0.1℃ 整数或 nil（无效值不参与报警判断）
function M.update(temps, thresholds)
    for i = 1, 2 do
        local v = temps[i]
        if v then
            local th = thresholds[i]
            local nl = judge(v, th.warn, th.alarm, level[i])
            if nl > level[i] then
                add_record(i, nl, v)
                level[i] = nl
            elseif nl < level[i] then
                -- 恢复：把该通道未恢复的记录标为已恢复
                for _, r in ipairs(records) do
                    if r.ch == i and not r.resolved then
                        r.resolved = true
                        if r.acked then r.state = "已恢复" end
                    end
                end
                level[i] = nl
                seq = seq + 1                       -- 状态变了，让界面重画一次
                fire("recover", nil)
            end
        end
    end
    return level
end

function M.level(i) return level[i] end
function M.records() return records end
function M.count() return #records end
-- 记录版本号：UI 刷新与落盘只在变化时触发，避免高频写 flash
function M.seq() return seq end

function M.any_active()
    return level[1] > 0 or level[2] > 0
end

function M.mute()  muted = true;  return muted end
function M.is_muted() return muted end

function M.toggle_mute()
    muted = not muted
    return muted
end

-- 复位：未恢复的保留但标为已确认；已恢复的清掉
function M.reset()
    local kept = {}
    for _, r in ipairs(records) do
        if not r.resolved then
            r.acked = true
            r.state = "已确认"
            kept[#kept + 1] = r
        end
    end
    records = kept
    muted = false
    seq = seq + 1
    fire("reset")
    return #records
end

function M.set_records(list)
    records = list or {}
    if #records > MAX then
        local t = {}
        for i = 1, MAX do t[i] = records[i] end
        records = t
    end
end

function M.subscribe(fn) listeners[#listeners + 1] = fn end

-- 供 UI 显示用的状态文案
function M.pill_text(i)
    if level[i] == 2 then return "报警", cfg.color.alarm end
    if level[i] == 1 then return "预警", cfg.color.warn end
    return "正常", cfg.color.ok
end

return M
