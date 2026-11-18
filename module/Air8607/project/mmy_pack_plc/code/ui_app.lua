--[[
@module  ui_app
@summary 界面层：main.xml 载入、按绑定表刷数、表格与高亮块、事件分派
@version 1.0.0
@date    2026.11.17
@usage
界面自己不存数据，刷新流程分三步：
1、ui_vars 的绑定表逐条 set_text；
2、当前页特有的部分单独刷（工位高亮、步序高亮、三张点位表、强制标记）；
3、最后 plcui.refresh() 统一提交，避免每个 setter 各自刷一帧。
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
local chart_seq = -1          -- 已处理的工步序号

-- 工位拓扑几何：4 列 × 2 行，与 main.xml 的 st_b* 一致
local ST_X, ST_Y, ST_PITCH, ST_GAP = 26, 202, 152, 102
-- 步序表几何：行距 38，与 sp_* 一致
local SP_X, SP_Y, SP_PITCH = 26, 152, 38

local XML_CANDIDATES = { "/luadb/main.xml", "/res/main.xml", "/main.xml" }

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

-- ==================== 绑定表刷数 ====================
local function apply_bind(b, v)
    if v == nil then return end
    local o = node(b.id)
    if not o then return end
    if b.kind == "hidden" then
        try(o.set_hidden, "set_hidden", o, v == true)
    elseif b.kind == "disabled" then
        try(o.set_disabled, "set_disabled", o, v == true)
    else
        try(o.set_text, "set_text", o, tostring(v))
    end
end

-- ==================== 表格 ====================
--[[ 一张表：表头一行 + 数据若干行；row 从 1 开始，1 是表头 ]]
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

--[[ 三张静态表的初值：表格在 XML 里只有行列，文字必须由 Lua 灌一次 ]]
local LOCK_ROWS = {
    { "安全门闭合", "○", "○", "○", "○" },
    { "上游有料",   "○", "○", "●", "●" },
    { "工位空闲",   "○", "○", "○", "○" },
    { "配方已下发", "○", "○", "○", "○" },
    { "气密合格",   "●", "●", "●", "○" },
}

local INFO_ROWS = {
    { "设备名称",   "PACK-3 储能模组装配线" },
    { "产线编号",   "LN-PACK-03" },
    { "控制器",     "CTRL-1500 / V3.2.7" },
    { "工位数",     "7" },
    { "节拍设计值", "42 s / 模组" },
}

local function refresh_io_tables(extra)
    if not extra then return end
    fill_table("tb_di", { "位号", "名称", "状态" }, extra.di)
    fill_table("tb_do", { "位号", "名称", "状态" }, extra.do_)
    fill_table("tb_ai", { "通道", "名称", "值" }, extra.ai)

    -- 强制标记：只切显隐，不动颜色
    for i = 1, 3 do
        local on = extra.force and extra.force[i] == true
        local m = node("fc_m" .. (i - 1))
        if m then try(m.set_hidden, "set_hidden", m, not on) end
        local s = node("fc_s" .. (i - 1))
        if s then try(s.set_text, "set_text", s, on and "强制" or "实时") end
    end
end

-- ==================== 高亮块 ====================
local function move_station_hl(idx)
    local o = node("st_hl")
    if not o then return end
    local i = idx - 1
    local x = ST_X + (i % 4) * ST_PITCH
    local y = ST_Y + math.floor(i / 4) * ST_GAP + 8
    try(o.set_pos, "set_pos", o, x, y)
end

local function move_step_hl(idx)
    local o = node("sp_hl")
    if not o then return end
    try(o.set_pos, "set_pos", o, SP_X, SP_Y + (idx - 1) * SP_PITCH)
end

-- ==================== 对外：加载与切页 ====================
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

    -- 曲线采样：200ms 一次，只在趋势页真正干活，其余页第一行就返回
    sys.timerLoopStart(ui_app.chart_tick, 200)
    return true
end

--[[ 切页后延时刷新：句柄要重新 find，不能同步访问新页组件 ]]
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

-- ==================== 曲线滚动 ====================
--[[ chart 没有 clear，用的是固定长度环形缓冲：add_point 把新点放最右、其余左移。
     所以这里不清空，只按 200 ms 持续追加，曲线自然滚动。
     限值线（hi/lo/lim）不追加，保持 XML 里的常量，画出来是两条水平参考线。 ]]
--[[ 把某一系列整条置为同一个值：既清掉上一模组的残影，也把环形游标拨回起点 ]]
local function flatten(chart, sid, value)
    if not chart or not value then return end
    -- 点数以 XML 为准：set_values 要求长度严格等于 point-count，写死常量迟早脱节
    local ok, st = pcall(chart.state, chart)
    local n = ok and st and st.point_count or nil
    if not n or n < 2 then return end
    local buf = {}
    for i = 1, n do buf[i] = value end
    try(chart.set_values, "set_values", chart, sid, buf)
end

function ui_app.chart_tick()
    if not xml or cur_page ~= "trend" then return end
    local ct = node("ch_tq")
    local lk = node("ch_lk")
    if not ct or not lk then return end

    -- 进入新工步时先把曲线压平，曲线就从左侧逐点画起，不会和上一模组拼接
    local seq = data_app.step_seq()
    if seq ~= chart_seq then
        chart_seq = seq
        local key = data_app.step_key()
        local a, b, lp = data_app.base_of(key)
        if a then
            flatten(ct, "m1", a)
            flatten(ct, "m3", b)
            data_app.reset_curve()
        elseif lp then
            flatten(lk, "pv", lp)
            data_app.reset_curve()
        end
    end

    local t1, t3, lp = data_app.sample()
    local dirty = false
    if t1 then
        try(ct.add_point, "add_point", ct, "m1", t1)
        try(ct.add_point, "add_point", ct, "m3", t3)
        dirty = true
    end
    if lp then
        try(lk.add_point, "add_point", lk, "pv", lp)
        dirty = true
    end
    if dirty then pcall(plcui.refresh) end
end

-- ==================== 刷新当前页 ====================
function ui_app.refresh()
    if not xml then return end
    local v, extra = data_app.get()

    local list = ui_vars.bind_list(cur_page)
    for i = 1, #list do
        apply_bind(list[i], v[list[i].var])
    end

    if cur_page == "overview" then
        if extra then move_station_hl(extra.step_i) end
    elseif cur_page == "trend" then
        -- 拧紧结果：4 轴一轮，判定与复拧列为定值
        local rows = {}
        for i = 1, 4 do
            rows[i] = {
                "M" .. i,
                v["ax_v" .. (i - 1)] or "--",
                v["ax_a" .. (i - 1)] or "--",
                "合格",
                (i == 3) and "1" or "0",
            }
        end
        fill_table("tb_tq", { "轴", "扭矩 N·m", "角度", "判定", "复拧" }, rows)
    elseif cur_page == "step" then
        if extra then
            move_step_hl(extra.step_i)
            -- 已完成的工步点亮绿点：PLCUI 改不了字色，用色块表达进度
            for i = 1, 7 do
                local d = node("sp_d" .. (i - 1))
                if d then try(d.set_hidden, "set_hidden", d, not (i < extra.step_i)) end
            end
        end
        fill_table("tb_lk", { "联锁条件", "上料", "堆叠", "焊接", "拧紧" }, LOCK_ROWS)
    elseif cur_page == "io" then
        refresh_io_tables(extra)
    elseif cur_page == "sys" then
        fill_table("tb_if", { "项目", "值" }, INFO_ROWS)
    end

    pcall(plcui.refresh)
end

-- ==================== 事件 ====================
local function go(page)
    return function() ui_app.show(page) end
end

local function set_brightness(v)
    data_app.set_bright(v)
    -- 三档按钮要同步滑块位置，否则读数变了、滑块还停在原处
    local sl = node("br_sl")
    if sl then try(sl.set_value, "set_value", sl, data_app.bright()) end
    ui_app.refresh()
end

ui_app.handlers = {
    go_ov = go("overview"),
    go_tr = go("trend"),
    go_st = go("step"),
    go_io = go("io"),
    go_sy = go("sys"),

    -- 强制表：点一下切换，强制值优先于实时映像
    fc_0 = function() data_app.force(1); ui_app.refresh() end,
    fc_1 = function() data_app.force(2); ui_app.refresh() end,
    fc_2 = function() data_app.force(3); ui_app.refresh() end,
    fc_clear = function() data_app.clear_force(); ui_app.refresh() end,

    -- 背光：滑块拖动时取当前值；三档按钮直接给值
    set_bright = function()
        local sl = node("br_sl")
        if sl then
            local ok, val = pcall(sl.get_value, sl)
            if ok and val then set_brightness(val) end
        end
    end,
    br_night = function() set_brightness(32) end,
    br_std = function() set_brightness(82) end,
    br_high = function() set_brightness(100) end,
}

return ui_app
