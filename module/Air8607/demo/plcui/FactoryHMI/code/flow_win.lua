--[[
@module  flow_win
@summary 工艺流程页窗口模块
@version 1.2
@date    2026.11.11
@usage
本文件为 FactoryHMI 的工艺页（flow）窗口模块：
1、refresh 刷新设备两态图、罐内液位、灌装喷嘴、产品箱、六张 KPI、位号标签；
2、flow_tick 每 320ms 交替显隐两张错相位流光图，形成管道流动感；
3、设备点击（手动模式下）：P-101 / FV-101 / P-102 / FV-102；
   自动模式与急停只提示不动手。
组件访问统一走 ui_util，避免 nil 崩溃。

对外接口：
1、flow_win.bind(xml)
2、flow_win.refresh()
3、flow_win.flow_tick()
4、flow_win.hint(msg)
5~8、on_dev_p101 / on_dev_fv101 / on_dev_p102 / on_dev_fv102
]]

local M = {}

local data_sim = require "data_sim"
local U = require "ui_util"

local xml_handle = nil
local PAGE = "flow"
local flow_phase = false
local hint_timer = nil

--[[
取当前页 id，plcui 不可用时返回 nil（不抛错）；
]]
local function cur_page()
    if not plcui or not plcui.status then return nil end
    local ok, st = pcall(plcui.status)
    if ok and st then return st.page end
    return nil
end

--[[
绑定 xml 句柄；
]]
function M.bind(xml)
    xml_handle = xml
end

--[[
页脚提示，2.2 秒后自动清空；
]]
function M.hint(msg)
    if not xml_handle then return end
    U.set(xml_handle, PAGE, "msg", msg)
    if hint_timer then
        sys.timerStop(hint_timer)
        hint_timer = nil
    end
    hint_timer = sys.timerStart(M.clear_hint, 2200)
end

--[[
清空提示；
]]
function M.clear_hint()
    hint_timer = nil
    U.set(xml_handle, PAGE, "msg", "")
end

--[[
液位档位 0~4；
]]
local function level_src(prefix, ratio)
    local idx = math.floor(ratio / 25)
    if idx < 0 then idx = 0 end
    if idx > 4 then idx = 4 end
    return prefix .. "_" .. tostring(idx)
end

--[[
刷新本页全部动态组件；
]]
function M.refresh()
    if not xml_handle then return end
    local sim = data_sim
    local x = xml_handle

    U.src(x, PAGE, "dev_p101", sim.dev_on("p1") and "p101_on" or "p101_off")
    U.src(x, PAGE, "dev_p102", sim.dev_on("p2") and "p102_on" or "p102_off")
    U.src(x, PAGE, "dev_fv101", sim.dev_on("v1") and "fv101_open" or "fv101_close")
    U.src(x, PAGE, "dev_fv102", sim.dev_on("v2") and "fv102_open" or "fv102_close")
    U.src(x, PAGE, "dev_e101", sim.dev_on("e101") and "e101_on" or "e101_off")

    U.src(x, PAGE, "lv_a", level_src("lv_a", sim.tankA))
    U.src(x, PAGE, "lv_b", level_src("lv_b", sim.tankB))

    local pouring = sim.dev_on("p1") and sim.v1 > 0 and sim.dev_on("v2")
    U.src(x, PAGE, "nozzle", pouring and "nozzle_run" or "nozzle_idle")
    U.src(x, PAGE, "box4", pouring and "box_full" or "box")

    U.set(x, PAGE, "tag_fv101", "FV-101 " .. tostring(sim.v1) .. "%")

    U.set(x, PAGE, "k1_v", sim.fmt(sim.temp, 1))
    U.set(x, PAGE, "k2_v", sim.fmt(sim.press, 2))
    U.set(x, PAGE, "k3_v", sim.fmt(sim.flow, 1))
    U.set(x, PAGE, "k4_v", tostring(math.floor(sim.tankB)))
    U.set(x, PAGE, "k5_v", tostring(sim.count))
    U.set(x, PAGE, "k6_v", string.format("%02d:%02d",
        math.floor(sim.sec / 3600) % 100, math.floor(sim.sec % 3600 / 60)))
end

--[[
管道流光：两张错相位图交替显隐；
]]
function M.flow_tick()
    if not xml_handle then return end
    if cur_page() ~= PAGE then return end

    if not data_sim.dev_on("p1") or data_sim.v1 <= 0 then
        if flow_phase then
            U.hide(xml_handle, PAGE, "pf_a", true)
            U.hide(xml_handle, PAGE, "pf_b", true)
            flow_phase = false
        end
        return
    end

    flow_phase = not flow_phase
    U.hide(xml_handle, PAGE, "pf_a", not flow_phase)
    U.hide(xml_handle, PAGE, "pf_b", flow_phase)
end

--[[
手动操作守卫；
]]
local function can_operate()
    if data_sim.estop then
        M.hint("急停状态，请到「报警」页复位")
        return false
    end
    if data_sim.mode ~= "manual" then
        M.hint("自动模式不可手动操作，点顶栏状态切换手动")
        return false
    end
    return true
end

--[[
P-101 进料泵；
]]
function M.on_dev_p101(event)
    if not can_operate() then return end
    data_sim.p1 = not data_sim.p1
    M.hint(data_sim.p1 and "P-101 进料泵 启动" or "P-101 进料泵 停止")
    M.refresh()
end

--[[
P-102 循环泵；
]]
function M.on_dev_p102(event)
    if not can_operate() then return end
    data_sim.p2 = not data_sim.p2
    M.hint(data_sim.p2 and "P-102 循环泵 启动" or "P-102 循环泵 停止")
    M.refresh()
end

--[[
FV-101 调节阀：0% 与 64% 互切；
]]
function M.on_dev_fv101(event)
    if not can_operate() then return end
    if data_sim.v1 > 0 then
        data_sim.v1 = 0
        M.hint("FV-101 调节阀 已关闭")
    else
        data_sim.v1 = 64
        M.hint("FV-101 调节阀 开度 64%")
    end
    M.refresh()
end

--[[
FV-102 灌装阀；
]]
function M.on_dev_fv102(event)
    if not can_operate() then return end
    data_sim.v2 = not data_sim.v2
    M.hint(data_sim.v2 and "FV-102 灌装阀 打开" or "FV-102 灌装阀 关闭")
    M.refresh()
end

return M
