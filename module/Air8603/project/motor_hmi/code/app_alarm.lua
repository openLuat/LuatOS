--[[
@module  app_alarm
@summary 报警状态机：故障码 / 电机过载 / 通讯离线 / 急停，记录并可弹窗
@version 1.0.0
@date    2026.11.12

判定要点：
- 变频器故障码非 0 即报警，过载类（OL / OL1）单独标注为「过载」；
- 只在「由正常变为故障」的那一拍记一条，不会每 500ms 重复刷屏；
- 通讯连续失败判离线，恢复后自动消警（不记记录，只做状态提示）；
- 记录落 fskv，掉电不丢，最多 conf.alarm.max 条。
]]
local M = {}

local conf = require "conf"
local data = require "app_data"
local store = require "app_store"
local seq = require "app_seq"

M.recs = {}            -- 报警记录，[1] 为最新
M.lv = 0               -- 当前最高等级：0 正常 / 1 警告 / 2 报警
M.version = 0          -- 记录变化计数，UI 用它判断要不要重绘

local listeners = {}
local last_fault = {}  -- 每台上一次看到的故障码
local last_online = {} -- 每台上一次在线状态
local estop_flag = false

--[[
注册变化回调
@param fn function(evt)  evt = "new" / "clear"
@return nil
]]
function M.on_change(fn)
    listeners[#listeners + 1] = fn
end

local function notify(evt)
    M.version = M.version + 1
    for _, fn in ipairs(listeners) do
        pcall(fn, evt)
    end
end

--[[
故障码转文本
@param code number
@return string
]]
function M.fault_text(code)
    if not code or code == 0 then return "正常" end
    return conf.faults[code] or ("故障码 " .. tostring(code))
end

--[[
追加一条记录
@param motor string 电机名
@param text string 描述
@param code number|nil 故障码
@return nil
]]
local function add(motor, text, code)
    table.insert(M.recs, 1, {
        t = os.date("%m-%d %H:%M:%S"),
        m = motor,
        text = text,
        code = code or 0,
    })
    while #M.recs > conf.alarm.max do
        table.remove(M.recs)
    end
    store.save_alarms(M.recs)
    notify("new")
end

--[[
初始化：载入历史记录
@return nil
]]
function M.init()
    M.recs = store.load_alarms()
    last_fault = {}
    last_online = {}
    M.lv = 0
end

--[[
每拍调用：扫描所有电机状态，产生新报警
@return nil
]]
function M.scan()
    local top = 0

    for i, c in ipairs(conf.motors) do
        local d = data.get(i)
        if d then
            -- 1) 故障码
            local f = d.online and (d.fault or 0) or 0
            local lf = last_fault[i] or 0

            if f ~= 0 and f ~= lf then
                local is_ol = conf.overload_codes[f] == true
                add(c.name, (is_ol and "电机过载：" or "变频器故障：") .. M.fault_text(f), f)
            end
            last_fault[i] = f

            if d.online and f ~= 0 then
                top = 2
            end

            -- 2) 在线状态
            local on = d.online
            local lon = last_online[i]
            if lon == true and not on then
                add(c.name, "通讯中断", 0)
                top = 2
            end
            last_online[i] = on

            if not on then
                top = math.max(top, 1)
            end
        end
    end

    -- 3) 急停
    if seq.estop and not estop_flag then
        add("系统", "急停按下", 0)
        top = 2
    end
    estop_flag = seq.estop

    if top ~= M.lv then
        M.lv = top
    end
end

--[[
清空记录
@return nil
]]
function M.clear()
    M.recs = {}
    store.save_alarms(M.recs)
    M.lv = 0
    notify("clear")
end

--[[
记录条数
@return number
]]
function M.count()
    return #M.recs
end

return M
