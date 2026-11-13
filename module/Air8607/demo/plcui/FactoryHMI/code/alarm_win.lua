--[[
@module  alarm_win
@summary 报警页窗口模块
@version 1.1
@date    2026.11.10
@usage
本文件为 FactoryHMI 的报警页（alarm）窗口模块：
1、refresh 把 data_sim.alarms 写进 9 行 x 5 列表格（首行表头），
   刷新三张统计卡与行选中高亮；
2、行选中：8 个透明热区图 ar1~ar8 覆盖在表格行上（PLCUI 仅 image 可点击）；
3、确认选中 / 全部确认 / 报警复位（复位同时解除急停并停机）。

对外接口：
1、alarm_win.bind(xml)
2、alarm_win.refresh()
3、alarm_win.hint(msg)
4、on_row / on_ack_selected / on_ack_all / on_reset
]]

local M = {}

local data_sim = require "data_sim"
local topbar = require "topbar"
local U = require "ui_util"

local xml_handle = nil
local PAGE = "alarm"
local ROWS = 8

local LV_TEXT = {crit = "危急", warn = "警告", info = "提示"}

local hint_timer = nil

--[[
绑定 xml 句柄；
]]
function M.bind(xml)
    xml_handle = xml
end

--[[
页脚提示；
]]
function M.hint(msg)
    if not xml_handle then return end
    U.set(xml_handle, PAGE, "n1", msg)
    U.set(xml_handle, PAGE, "n2", "")
    if hint_timer then
        sys.timerStop(hint_timer)
        hint_timer = nil
    end
    hint_timer = sys.timerStart(M.clear_hint, 2600)
end

--[[
恢复页脚；
]]
function M.clear_hint()
    hint_timer = nil
    U.set(xml_handle, PAGE, "n1", "复位清除全部记录并解除急停；")
    U.set(xml_handle, PAGE, "n2", "复位后需重新按「启动」。")
end

--[[
刷新报警表格、统计卡与行高亮；
]]
function M.refresh()
    if not xml_handle then return end
    local x = xml_handle
    local i

    local unack, crit, warn, ack = 0, 0, 0, 0

    for i = 1, ROWS do
        local a = data_sim.alarms[i]
        if a then
            U.cell(x, PAGE, "alarm_tb", i + 1, 1, a.t)
            U.cell(x, PAGE, "alarm_tb", i + 1, 2, a.code)
            U.cell(x, PAGE, "alarm_tb", i + 1, 3, a.msg)
            U.cell(x, PAGE, "alarm_tb", i + 1, 4, LV_TEXT[a.lv] or a.lv)
            U.cell(x, PAGE, "alarm_tb", i + 1, 5, a.ack and "已确认" or "待确认")
            if not a.ack then
                unack = unack + 1
                if a.lv == "crit" then crit = crit + 1 end
                if a.lv == "warn" then warn = warn + 1 end
            end
            if a.ack then ack = ack + 1 end
        else
            U.cell(x, PAGE, "alarm_tb", i + 1, 1, "")
            U.cell(x, PAGE, "alarm_tb", i + 1, 2, "")
            U.cell(x, PAGE, "alarm_tb", i + 1, 3, "")
            U.cell(x, PAGE, "alarm_tb", i + 1, 4, "")
            U.cell(x, PAGE, "alarm_tb", i + 1, 5, "")
        end
        U.chk(x, PAGE, "ar" .. i, data_sim.sel_alarm == i)
    end

    U.set(x, PAGE, "s1_v", tostring(crit))
    U.set(x, PAGE, "s2_v", tostring(warn))
    U.set(x, PAGE, "s3_v", tostring(ack))
    U.set(x, PAGE, "h_sub", "共 " .. tostring(#data_sim.alarms) ..
        " 条 · 未确认 " .. tostring(unack) .. " 条")
end

--[[
行点击选中；
]]
function M.on_row(event)
    local idx = tonumber(string.match(event.id, "^ar(%d)$"))
    if not idx then return end
    if idx > #data_sim.alarms then
        M.hint("该行没有报警记录")
        return
    end
    if data_sim.sel_alarm == idx then
        data_sim.sel_alarm = -1
    else
        data_sim.sel_alarm = idx
    end
    M.refresh()
end

--[[
确认选中行；
]]
function M.on_ack_selected(event)
    local idx = data_sim.sel_alarm
    if idx < 1 or idx > #data_sim.alarms then
        M.hint("请先点一行报警再确认")
        return
    end
    data_sim.alarms[idx].ack = true
    M.refresh()
    topbar.refresh(xml_handle, PAGE)
    M.hint("已确认 " .. data_sim.alarms[idx].code)
end

--[[
全部确认；
]]
function M.on_ack_all(event)
    local i
    for i = 1, #data_sim.alarms do
        data_sim.alarms[i].ack = true
    end
    M.refresh()
    topbar.refresh(xml_handle, PAGE)
    M.hint("已全部确认")
end

--[[
报警复位：清空记录、解除急停、停机；
]]
function M.on_reset(event)
    data_sim.alarms = {}
    data_sim.sel_alarm = -1
    data_sim.estop = false
    data_sim.running = false
    data_sim.p1 = false
    data_sim.p2 = false
    data_sim.v2 = false
    M.refresh()
    topbar.refresh(xml_handle, PAGE)
    M.hint("报警已复位 · 请重新按「启动」")
end

return M
