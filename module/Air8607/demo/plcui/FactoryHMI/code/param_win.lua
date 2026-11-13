--[[
@module  param_win
@summary 参数设定页窗口模块
@version 1.1
@date    2026.11.10
@usage
本文件为 FactoryHMI 的参数页（param）窗口模块：
1、8 组设定值（textarea + 数字键盘），每组带范围校验，越界还原原值并提示；
2、三种配方卡可点击选中，选中态换卡底与勾选圆点；
3、应用配方把灌装量 / 温度 / 速度写回设定值。

对外接口：
1、param_win.bind(xml)
2、param_win.refresh()
3、param_win.hint(msg)
4、on_submit / on_cancel / on_recipe_pick / on_apply
]]

local M = {}

local data_sim = require "data_sim"
local U = require "ui_util"

local xml_handle = nil
local PAGE = "param"

local PARAMS = {
    {id = "p1", key = "tempSet",  name = "目标温度",   min = 30,  max = 110, dec = 1},
    {id = "p2", key = "pressSet", name = "目标压力",   min = 0.2, max = 0.95, dec = 2},
    {id = "p3", key = "v1",       name = "进料阀开度", min = 0,   max = 100, dec = 0},
    {id = "p4", key = "fillMl",   name = "灌装量",     min = 50,  max = 1000, dec = 0},
    {id = "p5", key = "speed",    name = "灌装速度",   min = 10,  max = 100, dec = 0},
    {id = "p6", key = "rpm",      name = "搅拌转速",   min = 100, max = 600, dec = 0},
    {id = "p7", key = "kp",       name = "PID·Kp",     min = 0,   max = 20,  dec = 1},
    {id = "p8", key = "ki",       name = "PID·Ki",     min = 0,   max = 10,  dec = 1},
}

local RECIPES = {
    {no = "01", name = "标准配方 250ml", fillMl = 250, tempSet = 80.0, speed = 70},
    {no = "02", name = "大瓶配方 500ml", fillMl = 500, tempSet = 84.0, speed = 55},
    {no = "03", name = "小瓶配方 120ml", fillMl = 120, tempSet = 76.0, speed = 88},
}

local BY_ID = {}
for i = 1, #PARAMS do
    BY_ID[PARAMS[i].id] = PARAMS[i]
end

local hint_timer = nil

--[[
绑定 xml 句柄；
]]
function M.bind(xml)
    xml_handle = xml
end

--[[
副标题提示，2.4 秒恢复；
]]
function M.hint(msg)
    if not xml_handle then return end
    U.set(xml_handle, PAGE, "h_sub", msg)
    if hint_timer then
        sys.timerStop(hint_timer)
        hint_timer = nil
    end
    hint_timer = sys.timerStart(M.clear_hint, 2400)
end

--[[
恢复副标题；
]]
function M.clear_hint()
    hint_timer = nil
    U.set(xml_handle, PAGE, "h_sub", "工艺参数 · 点击数值弹出键盘")
end

--[[
刷新输入框回显与配方选中态；
]]
function M.refresh()
    if not xml_handle then return end
    local x = xml_handle
    local i

    for i = 1, #PARAMS do
        local def = PARAMS[i]
        U.set(x, PAGE, def.id, data_sim.fmt(data_sim[def.key], def.dec))
    end

    for i = 1, #RECIPES do
        local picked = (data_sim.recipe == i)
        U.chk(x, PAGE, "r" .. i, picked)
        U.src(x, PAGE, "r" .. i .. "_chk", picked and "chk_on" or "chk_off")
    end

    local cur = RECIPES[data_sim.recipe]
    if cur then
        U.set(x, PAGE, "r_sub", "当前 " .. cur.no .. " " .. cur.name)
    end
end

--[[
一组设定值提交（8 组共用，按 event.id 分发）；
]]
function M.on_submit(event)
    local def = BY_ID[event.id]
    if not def then return end
    if not xml_handle then return end

    local value = tonumber(event.text)
    if not value then
        U.set(xml_handle, PAGE, def.id, data_sim.fmt(data_sim[def.key], def.dec))
        M.hint(def.name .. " 输入无效")
        return
    end
    if value < def.min or value > def.max then
        U.set(xml_handle, PAGE, def.id, data_sim.fmt(data_sim[def.key], def.dec))
        M.hint(def.name .. " 超出范围 " .. tostring(def.min) .. " ~ " .. tostring(def.max))
        return
    end

    data_sim[def.key] = value
    U.set(xml_handle, PAGE, def.id, data_sim.fmt(value, def.dec))
    M.hint(def.name .. " 已设为 " .. data_sim.fmt(value, def.dec))
end

--[[
取消编辑；
]]
function M.on_cancel(event)
    M.hint("已取消编辑")
end

--[[
配方卡点击；
]]
function M.on_recipe_pick(event)
    local idx = tonumber(string.match(event.id, "^r(%d)$"))
    if not idx or idx < 1 or idx > #RECIPES then return end
    data_sim.recipe = idx
    M.refresh()
    M.hint("已选中 " .. RECIPES[idx].name)
end

--[[
应用选中配方；
]]
function M.on_apply(event)
    local r = RECIPES[data_sim.recipe]
    if not r then return end
    data_sim.fillMl = r.fillMl
    data_sim.tempSet = r.tempSet
    data_sim.speed = r.speed
    M.refresh()
    M.hint("已应用：" .. r.name)
end

return M
