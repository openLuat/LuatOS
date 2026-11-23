--[[
@module  ui_app
@summary 界面层：单页载入、右侧三视图切换、库位格显隐搬运、作业标记移动
@version 1.0.0
@date    2026.11.22
@usage
1、ui_app.load    plcui.init + 载入 main.xml + 起 3 秒搬运定时器；
2、ui_app.refresh 按绑定表刷顶部计数、状态带与任务队列；
3、搬运：data_app.pick_move 给出一个出库格与一个入库格，只对这两个格调 set_hidden；
4、作业标记：两台堆垛机各一个赭石块，用 set_pos 移到目标格。
三视图用「预置胶囊 + 深浅两套文字」显隐切换——PLCUI 运行时改不了颜色。
本文件对外接口 4 个：load / refresh / handlers / cur_view。
]]

local ui_app = {}

local SCREEN_W, SCREEN_H = 1024, 600

local data_app = require "data_app"
local ui_vars = require "ui_vars"

local xml = nil
local cur_view = 0
local warned = {}

local XML_CANDIDATES = { "/luadb/res/main.xml", "/res/main.xml", "/luadb/main.xml", "/main.xml" }

local function warn_once(key, msg, extra)
    if warned[key] then return end
    warned[key] = true
    log.warn("ui", msg, extra)
end

local function node(id)
    if not xml then return nil end
    local ok, o = pcall(xml.find, xml, "main", id)
    if ok then return o end
    return nil
end

local function try(fn, key, ...)
    if not fn then return false end
    local ok, ret, err = pcall(fn, ...)
    if not ok then
        warn_once(key, "调用失败:" .. key, tostring(ret))
        return false
    end
    if ret == nil and err then
        warn_once(key, "返回错误:" .. key, type(err) == "table" and (err.code or err.message) or tostring(err))
        return false
    end
    return true
end

local function set_hidden(id, hidden)
    local o = node(id)
    if o then try(o.set_hidden, "set_hidden", o, hidden) end
end

local function set_text(id, v)
    local o = node(id)
    if o then try(o.set_text, "set_text", o, tostring(v)) end
end

-- ==================== 视图切换 ====================
--[[ PLCUI 的 container 不继承 hidden：隐藏父容器不会隐藏子元素。
     所以三个视图的元素逐个登记，切换时统一开/关。 ]]
local function view_ids(i)
    local t = {}
    if i == 0 then
        t = { "s_cap", "s_id", "s_plt", "s_btn", "s_btn_t", "s_foot" }
        for k = 0, 4 do
            t[#t + 1] = "s_k" .. k
            t[#t + 1] = "s_v" .. k
            t[#t + 1] = "s_l" .. k
        end
    elseif i == 1 then
        t = { "t_cap", "t_cnt", "t_foot" }
        for k = 0, 4 do
            t[#t + 1] = "t_bg" .. k
            t[#t + 1] = "t_no" .. k
            t[#t + 1] = "t_op" .. k
            t[#t + 1] = "t_lo" .. k
            t[#t + 1] = "t_st" .. k
        end
    else
        t = { "a_cap", "m_cap" }
        for k = 0, 1 do
            t[#t + 1] = "a_bg" .. k
            t[#t + 1] = "a_bar" .. k
            t[#t + 1] = "a_tm" .. k
            t[#t + 1] = "a_tx" .. k
        end
        for k = 0, 3 do
            t[#t + 1] = "m_k" .. k
            t[#t + 1] = "m_v" .. k
            t[#t + 1] = "m_l" .. k
        end
    end
    return t
end

local function switch_view(i)
    cur_view = i
    for j = 0, 2 do
        local show = (j == i)
        local ids = view_ids(j)
        for _, id in ipairs(ids) do
            set_hidden(id, not show)
        end
    end
    -- chip 选中态：胶囊 + 白字 一起开关，深字反向
    for k = 0, 2 do
        local on = (k == i)
        set_hidden("chip" .. k .. "_pill", not on)
        set_hidden("chip" .. k .. "_wt", not on)
        set_hidden("chip" .. k .. "_dk", on)
    end
    pcall(plcui.refresh)
end

function ui_app.cur_view() return cur_view end

-- ==================== 搬运动画 ====================
--[[ 每 3 秒搬一次：出库格隐藏 1.2 秒再恢复为空（保持隐藏），入库格由隐藏变显示。
     为控制开销，只动这两个格子，不遍历 720 个。 ]]
local function move_marks(a, b)
    local r1, c1, l1 = data_app.split(a)
    local x1, y1 = data_app.cell_xy(r1, c1, l1)
    local m0 = node("mk0")
    if m0 then try(m0.set_pos, "set_pos", m0, x1, y1) end

    local r2, c2, l2 = data_app.split(b)
    local x2, y2 = data_app.cell_xy(r2, c2, l2)
    local m1 = node("mk1")
    if m1 then try(m1.set_pos, "set_pos", m1, x2, y2) end
end

function ui_app.move_tick()
    if not xml then return end
    local mv = data_app.pick_move()
    if not mv then return end

    local ro, co, lo = data_app.split(mv.out)
    local ri, ci, li = data_app.split(mv.into)

    -- 出库：该格由「在库」变空 -> 隐藏；入库：由空变在库 -> 显示
    set_hidden(data_app.cell_id(ro, co, lo), true)
    set_hidden(data_app.cell_id(ri, ci, li), false)

    move_marks(mv.out, mv.into)
    ui_app.refresh()
end

-- ==================== 加载 ====================
local function plcui_init()
    local errors = {}
    local ok1, ret1, err1 = pcall(plcui.init, { width = SCREEN_W, height = SCREEN_H })
    if ok1 and ret1 then return true, "init({width,height})" end
    errors[#errors + 1] = "init(table):" .. tostring(ok1 and err1 or ret1)
    local ok2, ret2, err2 = pcall(plcui.init, SCREEN_W, SCREEN_H)
    if ok2 and ret2 then return true, "init(w,h)" end
    errors[#errors + 1] = "init(w,h):" .. tostring(ok2 and err2 or ret2)
    return false, table.concat(errors, " | ")
end

local function load_doc(handlers)
    for i = 1, #XML_CANDIDATES do
        local path = XML_CANDIDATES[i]
        if io.exists(path) then
            local ok, doc, err = pcall(plcui.load, path, { handlers = handlers })
            if ok and doc then
                log.info("ui", "界面已加载", path)
                return doc
            end
            local why
            if type(err) == "table" then
                why = string.format("%s | code=%s attr=%s line=%s col=%s",
                    tostring(err.message), tostring(err.code), tostring(err.attribute),
                    tostring(err.line), tostring(err.column))
            else
                why = tostring(err or doc)
            end
            log.error("ui", "加载失败", path, why)
            return nil
        end
    end
    log.error("ui", "找不到 main.xml：检查 /res/main.xml")
    return nil
end

function ui_app.load(handlers)
    local ok, how = plcui_init()
    if not ok then
        log.error("ui", "plcui.init 失败", how)
        return false
    end
    log.info("ui", "plcui 初始化完成", how)

    xml = load_doc(handlers)
    if not xml then return false end

    pcall(xml.show, xml, "main")
    -- 页面组件延后实例化，此刻 find 拿不到句柄，必须等一拍
    sys.timerStart(function()
        switch_view(0)
        ui_app.refresh()
    end, 60)

    sys.timerLoopStart(ui_app.move_tick, 3000)
    return true
end

-- ==================== 刷新 ====================
function ui_app.refresh()
    if not xml then return end
    local v = data_app.get()
    local list = ui_vars.bind_list()
    for i = 1, #list do
        local b = list[i]
        if v[b.var] ~= nil then set_text(b.id, v[b.var]) end
    end
    pcall(plcui.refresh)
end

-- ==================== 事件 ====================
ui_app.handlers = {
    v_slot = function() switch_view(0) end,
    v_task = function() switch_view(1) end,
    v_alarm = function() switch_view(2) end,
    slot_out = function()
        log.info("ui", "指定出库：S3-14-3")
        ui_app.refresh()
    end,
}

return ui_app
