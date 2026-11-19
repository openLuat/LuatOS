--[[
@module  ui_app
@summary 界面层：main.xml 载入、按绑定表刷数、三张曲线滚动、表格与事件
@version 1.0.0
@date    2026.11.18
@usage
1、ui_app.load    plcui.init + 载入 main.xml + 进首页 + 起 200ms 曲线定时器；
2、ui_app.refresh 按 ui_vars 的绑定表刷当前页，再刷该页特有的表格；
3、ui_app.chart_tick  200ms 一次，把 6 个回路量追加到三张 chart 的环形缓冲。
切页后组件句柄要重新 find，所以 show() 里延时 40ms 再刷首帧。
本文件对外接口 4 个：load / show / refresh / handlers。
]]

local ui_app = {}

local SCREEN_W, SCREEN_H = 1024, 600

local data_app = require "data_app"
local ui_vars = require "ui_vars"

local xml = nil
local cur_page = ""
local warned = {}

-- 真机上 LuaDB 会把 code/ 下的目录树原样打包，res/main.xml 落在 /luadb/res/ 下；
-- 模拟器则把脚本目录挂成根，/res/main.xml 能直接命中，所以两种都要列
local XML_CANDIDATES = { "/luadb/res/main.xml", "/res/main.xml", "/luadb/main.xml", "/main.xml" }

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

-- ==================== 绑定 ====================
local function apply_bind(b, v)
    if v == nil then return end
    local o = node(b.id)
    if not o then return end
    if b.kind == "hidden" then
        try(o.set_hidden, "set_hidden", o, v == true)
    elseif b.kind == "size" then
        try(o.set_size, "set_size", o, math.max(1, math.floor(tonumber(v) or 1)), b.h or 10)
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

local INFO_ROWS = {
    { "设备名称", "CDU-1200 液冷散热机组" },
    { "位号", "CDU-A03" },
    { "控制器", "CTRL-1500 / V3.2.7" },
    { "额定制冷量", "1200 kW" },
    { "投运日期", "2026.03" },
}

-- ==================== 曲线 ====================
--[[ 三张图的点数以 XML 的 point-count 为准（30 / 30 / 50）。
     add_point 走固定长度环形缓冲：新点进最右、其余左移，天然滚动。 ]]
function ui_app.chart_tick()
    if not xml or cur_page ~= "trend" then return end
    -- 200ms 定时器只用来取样，真正入图按 1 Hz：温度这类慢量在 6 秒窗口里看不出变化，
    -- 1 Hz × 30/50 点 = 30/50 秒窗口，波动才读得出来
    local n = (ui_app._ck or 0) + 1
    ui_app._ck = n
    if n % 5 ~= 0 then return end
    local ct = node("ch_t")
    local cd = node("ch_d")
    local cv = node("ch_v")
    if not ct or not cd or not cv then return end

    local ts, tr, dp, p1, vl, p2 = data_app.sample()
    if ts then
        try(ct.add_point, "add_point", ct, "sup", ts)
        try(ct.add_point, "add_point", ct, "ret", tr)
        try(cd.add_point, "add_point", cd, "dp", dp)
        try(cv.add_point, "add_point", cv, "p1", p1)
        try(cv.add_point, "add_point", cv, "vl", vl)
        try(cv.add_point, "add_point", cv, "p2", p2)
        pcall(plcui.refresh)
    end
end

--[[ 首次进趋势页时把六条序列按当前值铺平：
     否则缓冲区左侧会留着 XML 初值（一条平线），和真实数据之间出现台阶 ]]
local seeded = false
local function seed_charts()
    if seeded then return end
    local ct, cd, cv = node("ch_t"), node("ch_d"), node("ch_v")
    if not (ct and cd and cv) then return end
    local function fill(chart, sid, val)
        local ok, st = pcall(chart.state, chart)
        local n = ok and st and st.point_count or nil
        if not n or n < 2 then return end
        local buf = {}
        for i = 1, n do buf[i] = val end
        try(chart.set_values, "set_values", chart, sid, buf)
    end
    local ts, tr, dp, p1, vl, p2 = data_app.sample()
    fill(ct, "sup", ts)
    fill(ct, "ret", tr)
    fill(cd, "dp", dp)
    fill(cv, "p1", p1)
    fill(cv, "vl", vl)
    fill(cv, "p2", p2)
    seeded = true
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

    -- 曲线采样：200ms 一次，不在趋势页时首行返回
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
    elseif cur_page == "trend" then
        seed_charts()
    elseif cur_page == "sys" then
        fill_table("tb_if", { "项目", "值" }, INFO_ROWS)
    end

    pcall(plcui.refresh)
end

-- ==================== 事件 ====================
local function go(page)
    return function() ui_app.show(page) end
end

-- 老固件（PLCUI 1.0.1）没有 slider，背光只有三档按钮 + 可伸缩填充条
local function set_brightness(v)
    data_app.set_bright(v)
    ui_app.refresh()
end

ui_app.handlers = {
    go_ov = go("overview"),
    go_lp = go("loop"),
    go_tr = go("trend"),
    go_io = go("io"),
    go_sy = go("sys"),

    fc_0 = function() data_app.force(1); ui_app.refresh() end,
    fc_clear = function() data_app.clear_force(); ui_app.refresh() end,

    br_night = function() set_brightness(32) end,
    br_std = function() set_brightness(82) end,
    br_high = function() set_brightness(100) end,
}

return ui_app
