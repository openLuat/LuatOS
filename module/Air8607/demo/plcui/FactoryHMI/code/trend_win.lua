--[[
@module  trend_win
@summary 实时趋势页窗口模块
@version 1.1
@date    2026.11.10
@usage
本文件为 FactoryHMI 的趋势页（trend）窗口模块：
1、init_values 用预置的 60 点历史灌满三条曲线；
2、refresh 每次推进一个采样点（chart:add_point 自动左移）并刷新统计卡；
3、三条曲线量纲不同，统一归一化到 0~100 再送进 chart。

对外接口：
1、trend_win.bind(xml)
2、trend_win.init_values()
3、trend_win.refresh()
]]

local M = {}

local data_sim = require "data_sim"
local U = require "ui_util"

local xml_handle = nil
local PAGE = "trend"

--[[
绑定 xml 句柄；
]]
function M.bind(xml)
    xml_handle = xml
end

--[[
灌满预置历史；
]]
function M.init_values()
    if not xml_handle then return end
    U.values(xml_handle, PAGE, "trend", "temp", data_sim.hist.temp)
    U.values(xml_handle, PAGE, "trend", "press", data_sim.hist.press)
    U.values(xml_handle, PAGE, "trend", "flow", data_sim.hist.flow)
end

--[[
推进一个采样点并刷新统计卡；
]]
function M.refresh()
    if not xml_handle then return end
    local x = xml_handle
    local sim = data_sim
    local last = sim.last
    if not last then return end

    U.point(x, PAGE, "trend", "temp", last.temp)
    U.point(x, PAGE, "trend", "press", last.press)
    U.point(x, PAGE, "trend", "flow", last.flow)

    U.set(x, PAGE, "t1_v1", sim.fmt(sim.temp, 1))
    U.set(x, PAGE, "t1_v2", sim.fmt(sim.t_max, 1))
    U.set(x, PAGE, "t1_v3", sim.fmt(sim.t_min, 1))

    U.set(x, PAGE, "t2_v1", sim.fmt(sim.press, 2))
    U.set(x, PAGE, "t2_v2", sim.fmt(sim.p_max, 2))
    U.set(x, PAGE, "t2_v3", sim.fmt(sim.p_min, 2))

    U.set(x, PAGE, "t3_v1", sim.fmt(sim.flow, 1))
    U.set(x, PAGE, "t3_v2", sim.fmt(sim.f_max, 1))
    U.set(x, PAGE, "t3_v3", sim.fmt(sim.f_min, 1))
end

return M
