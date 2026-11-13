--[[
@module  ui
@summary plcui 界面逻辑：事件处理 + 数据刷新
@version 1.0.0
@date    2026.11.12

=== 这一层在做什么 ===
plcui 的布局写在 main.xml，样式来自切图，本文件只做两件事：
  1. 把采集到的数据 set 进对应组件（set_text / set_src / set_hidden / set_cell）
  2. 把触摸事件转成业务调用（启停、复位、切页、改参数）

=== 三条硬约束（踩过就知道疼） ===
1. 事件回调里不能做阻塞串口操作 —— 回调不在协程里，sys.waitUntil 会抛
   "attempt to yield from outside a coroutine"。所有涉总线的动作都经 defer()
   丢到独立 task 里执行。
2. 切页之后旧句柄全部失效（再用报 E_OBJECT_CLOSED），所以不缓存句柄，
   每次都重新 find；切页后延时 30ms 再访问新页组件（plcui 官方要求）。
3. plcui 的 label 只能 set_text，改不了颜色；容器改不了背景。
   凡是「颜色随状态变」的元素，都做成多张切图 set_src，或拆成两个 label 叠层隐藏。
]]
local M = {}

local conf  = require "conf"
local data  = require "app_data"
local seq   = require "app_seq"
local alarm = require "app_alarm"
local store = require "app_store"

local x                    -- plcui 界面对象
local page = "main"        -- 当前页
local last_fail = 0        -- 已提示过的启动失败序号

-- ===== 基础工具 =====

--[[
绑定界面对象（plcui.load 之后调用）
@param xml userdata
@return nil
]]
function M.bind(xml)
    x = xml
end

--[[
把动作丢到独立协程里执行：plcui 事件回调不能 yield，串口读写在里面会崩
@param fn function
@return nil
]]
local function defer(fn)
    sys.taskInit(function()
        local ok, err = pcall(fn)
        if not ok then
            log.error("ui", "handler error", tostring(err))
        end
    end)
end

--[[
取当前页组件句柄（不缓存，切页后旧句柄会失效）
@param id string
@return userdata|nil
]]
local function f(id)
    if not x then return nil end
    local o, err = x:find(page, id)
    if not o then
        log.warn("ui", "find 失败", page, id, tostring(err and err.code or err))
    end
    return o
end

local function setText(id, txt)
    local o = f(id)
    if o then o:set_text(txt) end
end

local function setHidden(id, hide)
    local o = f(id)
    if o then o:set_hidden(hide and true or false) end
end

local function setSrc(id, src)
    local o = f(id)
    if o then o:set_src(src) end
end

--[[
把一段文本按第一个换行拆成两行（弹窗只有两行位置）
@param s string
@return string, string
]]
local function split2(s)
    s = s or ""
    local a, b = s:match("^([^\n]*)\n?(.*)$")
    return a or s, b or ""
end

--[[
故障码转成面板风格的短标识（Cu / OC / OL1 …）
@param code number
@return string
]]
local function fault_short(code)
    local name = conf.faults[code]
    if not name then return "Err" end
    local tail = name:match("(%a+%d*)$")
    return tail or "Err"
end

-- ===== 弹窗 =====

--[[
弹出阻塞提示（仅监控页有弹窗组件）
@param title string
@param text string 可含一个换行
@return boolean 是否成功弹出
]]
local MASK_CHILD = { "mbox", "mTtl", "mLine1", "mLine2", "mOk", "mOkT" }

--[[
显示或隐藏整个弹窗
@param showIt boolean
@return nil
]]
local function maskShow(showIt)
    setHidden("mask", not showIt)
    for _, id in ipairs(MASK_CHILD) do
        setHidden(id, not showIt)
    end
end

local function modal(title, text)
    if page ~= "main" then return false end
    local l1, l2 = split2(text)
    setText("mTtl", title)
    setText("mLine1", l1)
    setText("mLine2", l2)
    maskShow(true)
    return true
end

--[[
当前页没有弹窗组件时，退化为状态条提示
@param msg string
@return nil
]]
local function tipHere(msg)
    if page == "alarm" then
        setText("aTip", msg or "")
    elseif page == "settings" then
        setText("sTip", msg or "")
    end
end

-- ===== 刷新 =====

local function refreshMain()
    setText("clock", os.date("%H:%M:%S"))

    local n, total = data.count_running()
    setText("runTxt", string.format("运行 %d/%d 台", n, total))
    setHidden("estopTxt", not seq.estop)

    setSrc("dot", data.online and "img_dot_g" or "img_dot_r")
    setHidden("onlineOk", not data.online)
    setHidden("onlineBad", data.online)

    setText("stat", string.format("成功 %d  失败 %d", data.ok_count, data.err_count))

    local d = data.get(1)
    if not d then return end

    setText("motorName", d.name or "1 号电机")
    setText("motorSta", string.format("站号 %d", d.station or 0))

    -- 小数码窗：正常显示设定频率 F，故障时显示故障标识（与真机面板一致）
    if d.fault ~= 0 then
        setText("vfdNum", fault_short(d.fault))
    else
        setText("vfdNum", string.format("F%.1f", d.freq_cmd or 0))
    end

    setText("bigFreq", string.format("%.2f", d.freq_out or 0))
    setText("vCmd", string.format("%.2f Hz", d.freq_cmd or 0))
    setText("vCur", string.format("%.1f A", d.current or 0))

    -- 状态胶囊：颜色写死在切图里，按状态换图
    if (not d.online) or d.fault ~= 0 then
        setSrc("pill", "img_pill_err")
    elseif d.running then
        setSrc("pill", "img_pill_ok")
    else
        setSrc("pill", "img_pill_off")
    end

    -- 故障状态：绿/红两套 label 叠在同一位置，按状态显示其一
    local bad = d.online and (d.fault ~= 0)
    setHidden("vFltOk", bad)
    setHidden("vFltBad", not bad)
    if bad then
        setText("vFltBad", alarm.fault_text(d.fault))
    end

    -- 通讯状态
    setHidden("vComOk", not d.online)
    setHidden("vComBad", d.online)

    -- 启动命令发出但没生效：只提示一次
    if seq.fail_id ~= last_fail then
        last_fail = seq.fail_id
        modal("启动未生效", seq.fail_msg)
    end
end

local function refreshAlarm()
    local t = f("alarmTable")
    if not t then return end
    for i = 1, conf.alarm.max do
        local r = alarm.recs[i]
        local row = i + 1                       -- 第 1 行是表头
        t:set_cell(row, 1, r and r.t or "")
        t:set_cell(row, 2, r and r.m or "")
        t:set_cell(row, 3, r and r.text or (i == 1 and "暂无报警记录" or ""))
        t:set_cell(row, 4, (r and r.code and r.code ~= 0) and ("#" .. r.code) or "")
    end
    local ES = "急停锁存中，请到监控页复位后再启动"
    if seq.estop then
        setText("aTip", ES)
    else
        local o = f("aTip")
        if o and o:get_text() == ES then
            o:set_text("")
        end
    end
end

local function refreshSet()
    setText("sCur", string.format("当前生效：%d 秒，序列状态：%s",
        conf.seq.gap_s, seq.busy and "启动中" or "空闲"))
end

--[[
按当前页刷新（由主循环每 500ms 调用一次）
@return nil
]]
function M.refresh()
    if not x then return end
    if page == "main" then
        refreshMain()
    elseif page == "alarm" then
        refreshAlarm()
    else
        refreshSet()
    end
end

--[[
切页：延时 30ms 再刷新（plcui 要求，否则新页组件还没就绪）
@param pid string
@return nil
]]
local function show(pid)
    if not x then return end
    x:show(pid)
    page = pid
    sys.timerStart(function()
        local ok, err = pcall(M.refresh)
        if not ok then log.error("ui", "refresh after show", tostring(err)) end
    end, 30)
end

-- ===== 事件处理 =====

M.handlers = {}

M.handlers.nav_main = function()
    defer(function() show("main") end)
end

M.handlers.nav_alarm = function()
    defer(function() show("alarm") end)
end

M.handlers.nav_settings = function()
    defer(function() show("settings") end)
end

M.handlers.on_start = function()
    defer(function()
        if page ~= "main" then show("main") end
        local ok, err = seq.start_all()
        if not ok then
            modal("无法启动", err)
        end
    end)
end

M.handlers.on_stop = function()
    defer(function()
        local ok, err = seq.stop_all()
        if not ok then
            modal("停止失败", err)
        end
    end)
end

M.handlers.on_estop = function()
    defer(function()
        seq.estop_press()
    end)
end

M.handlers.on_reset_estop = function()
    defer(function()
        if not seq.estop then
            modal("无需复位", "当前没有急停锁存，可以直接启动。")
        else
            seq.estop_reset()
        end
    end)
end

--[[
故障复位：监控页弹窗，报警页用状态条（那边没有弹窗组件）
@return nil
]]
local function doResetFault()
    local n = seq.reset_fault()
    if n == 0 then
        if not modal("复位失败", "复位命令未发出，请检查通讯状态。") then
            tipHere("复位命令未发出，请检查通讯状态")
        end
    end
end

M.handlers.on_reset_fault = function()
    defer(doResetFault)
end

M.handlers.on_reset_fault2 = function()
    defer(doResetFault)
end

M.handlers.on_clear = function()
    defer(function()
        alarm.clear()
        if page ~= "alarm" then show("alarm") end
        M.refresh()
        tipHere("记录已清空")
    end)
end

M.handlers.on_modal_ok = function()
    defer(function()
        maskShow(false)
    end)
end

-- ===== 设置页 =====

--[[
读取并规范化输入框里的间隔值
@return number
]]
local function readGap()
    local o = f("inGap")
    local txt = o and o:get_text() or ""
    local v = tonumber(txt)
    if not v then v = conf.seq.gap_s end
    v = math.floor(v + 0.5)
    if v < conf.seq.gap_min then v = conf.seq.gap_min end
    if v > conf.seq.gap_max then v = conf.seq.gap_max end
    return v
end

M.handlers.on_gap_submit = function()
    defer(function()
        local v = readGap()
        conf.seq.gap_s = v
        store.save_gap(v)
        local o = f("inGap")
        if o then o:set_text(tostring(v)) end
        setText("sTip", string.format("已保存：%d 秒", v))
        M.refresh()
    end)
end

M.handlers.on_gap_cancel = function()
    defer(function()
        local o = f("inGap")
        if o then o:set_text(tostring(conf.seq.gap_s)) end
    end)
end

M.handlers.on_save = function()
    defer(function()
        local v = readGap()
        conf.seq.gap_s = v
        store.save_gap(v)
        local o = f("inGap")
        if o then o:set_text(tostring(v)) end
        setText("sTip", string.format("已保存：%d 秒", v))
        M.refresh()
    end)
end

M.handlers.on_default = function()
    defer(function()
        conf.seq.gap_s = 2
        store.save_gap(2)
        local o = f("inGap")
        if o then o:set_text("2") end
        setText("sTip", "已恢复默认 2 秒")
        M.refresh()
    end)
end

--[[
模拟故障：调试用，正式投产前应连同按钮一起删掉
@return nil
]]
M.handlers.on_sim_fault = function()
    defer(function()
        if page ~= "main" then
            show("main")
            sys.wait(100)          -- 等新页组件就绪，否则 find 拿不到句柄
        end
        data.force_fault(13)
        alarm.scan()
        modal("报警", "1 号电机：通讯超时 Cu")
    end)
end

-- ===== 启动 =====

--[[
首屏进入 + 启动刷新循环
@return nil
]]
function M.start()
    show("main")
    sys.taskInit(function()
        while true do
            sys.wait(500)
            local ok, err = pcall(M.refresh)
            if not ok then
                log.error("ui", "refresh error", tostring(err))
            end
        end
    end)
end

return M
