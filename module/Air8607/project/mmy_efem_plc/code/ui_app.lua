--[[
@module  ui_app
@summary 界面层：侧栏导航切换、按绑定表刷数、四张曲线滚动、表格与事件
@version 1.0.0
@date    2026.11.20
@usage
1、ui_app.load    plcui.init + 载入 main.xml + 进首页 + 起 200ms 曲线定时器；
2、ui_app.show    切页后延时 40ms 刷首帧，并把侧栏高亮块移到选中项；
3、ui_app.refresh 按 ui_vars 绑定表刷当前页，再刷该页表格。
侧栏选中态用「预制高亮块 + 绿条 set_pos 移动」实现——PLCUI 运行时改不了颜色。
本文件对外接口 4 个：load / show / refresh / handlers。
]]

local ui_app = {}

local SCREEN_W, SCREEN_H = 1024, 600

local data_app = require "data_app"
local ui_vars = require "ui_vars"

local xml = nil
local cur_page = ""
local warned = {}

local XML_CANDIDATES = { "/luadb/res/main.xml", "/res/main.xml", "/luadb/main.xml", "/main.xml" }

local PAGES = { "overview", "timing", "curve", "io", "sys" }

local function warn_once(key, msg, extra)
    if warned[key] then return end
    warned[key] = true
    log.warn("ui", msg, extra)
end

local function node(id)
    if not xml then return nil end
    local ok, o = pcall(xml.find, xml, cur_page, id)
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

local function apply_bind(b, v)
    if v == nil then return end
    local o = node(b.id)
    if not o then return end
    if b.kind == "hidden" then
        try(o.set_hidden, "set_hidden", o, v == true)
    else
        try(o.set_text, "set_text", o, tostring(v))
    end
end

-- ==================== 表格 ====================
local function fill_table(id, head, rows)
    local tb = node(id)
    if not tb then return end
    for c = 1, #head do
        try(tb.set_cell, "set_cell", tb, 1, c, head[c])
    end
    for r = 1, #rows do
        for c = 1, #rows[r] do
            try(tb.set_cell, "set_cell", tb, r + 1, c, rows[r][c])
        end
    end
end

-- ==================== 侧栏选中态 ====================
-- 高亮块与绿条按页在 XML 里预置（每页一份、位置固定），运行时不移动：
-- xml.show 之后组件是延后实例化的，此时 find 拿不到句柄，set_pos 会静默失败。

-- ==================== 曲线 ====================
function ui_app.chart_tick()
    if not xml or cur_page ~= "curve" then return end
    -- 200ms 取数，1 Hz 入图：30 点 = 30 秒窗口
    local n = (ui_app._ck or 0) + 1
    ui_app._ck = n
    if n % 5 ~= 0 then return end

    local vac, n2, cur, tmp = data_app.sample()
    local c1, c2 = node("ch1"), node("ch2")
    local c3, c4 = node("ch3"), node("ch4")
    if not (c1 and c2 and c3 and c4) then return end
    try(c1.add_point, "add_point", c1, "vac", vac)
    try(c2.add_point, "add_point", c2, "n2", n2)
    try(c3.add_point, "add_point", c3, "cur", cur)
    try(c4.add_point, "add_point", c4, "tmp", tmp)
    pcall(plcui.refresh)
end

-- ==================== 加载与切页 ====================
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

    cur_page = ""
    ui_app.show("overview")

    sys.timerLoopStart(ui_app.chart_tick, 200)
    return true
end

function ui_app.page_ready_cbfunc()
    ui_app.refresh()
end

function ui_app.show(page)
    if not xml then return false end
    if page == cur_page then
        ui_app.refresh()
        return true
    end
    local ok, ret = pcall(xml.show, xml, page)
    if not ok or ret == false then
        log.warn("ui", "切页失败", page, tostring(ret))
        return false
    end
    cur_page = page

    sys.timerStart(ui_app.page_ready_cbfunc, 40)
    return true
end

function ui_app.cur() return cur_page end

-- ==================== 刷新 ====================
function ui_app.refresh()
    if not xml then return end
    local v, extra = data_app.get()

    local list = ui_vars.bind_list(cur_page)
    for i = 1, #list do
        apply_bind(list[i], v[list[i].var])
    end

    if cur_page == "io" then
        if extra then
            fill_table("tb_di", { "位号", "名称", "状态" }, extra.di)
            fill_table("tb_do", { "位号", "名称", "状态" }, extra.do_)
            fill_table("tb_ai", { "通道", "名称", "值" }, extra.ai)
        end
    end

    pcall(plcui.refresh)
end

-- ==================== 事件 ====================
local function go(page)
    return function() ui_app.show(page) end
end

local function set_brightness(v)
    data_app.set_bright(v)
    ui_app.refresh()
end

ui_app.handlers = {
    go_ov = go("overview"),
    go_tm = go("timing"),
    go_cv = go("curve"),
    go_io = go("io"),
    go_sy = go("sys"),

    fc_clear = function() data_app.clear_force(); ui_app.refresh() end,

    br_1 = function() set_brightness(32) end,
    br_2 = function() set_brightness(82) end,
    br_3 = function() set_brightness(100) end,
}

return ui_app
