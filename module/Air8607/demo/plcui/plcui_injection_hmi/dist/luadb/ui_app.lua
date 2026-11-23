--[[
@module  ui_app
@summary 界面层：PLCUI 加载、页面切换、按绑定表刷数、事件分派
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件把 main.xml 里的组件搬成可操作的界面，自己不存业务数据：
1、ui_app.load        plcui.init（新旧固件两种签名都试）+ 载入 main.xml + 进首页；
2、ui_app.show        切页，回调里只登记，30ms 后再刷组件（避免 E_OBJECT_CLOSED）；
3、ui_app.refresh     把 data_app.get() 的结果按 ui_vars 的绑定表刷到当前页；
4、ui_app.tick_flow   管路流动条纹逐帧换图（200ms 一帧）；
5、ui_app.on_event    统一事件入口，main.xml 里每个 on-* 都在 handlers 表里注册。
急停做了两级确认：第一次按下进入「待确认」，5 秒内再按一次才真正停机，
用来替代网页版那个二次确认弹窗（PLCUI 没有模态弹窗组件）。
本文件的对外接口有 7 个（其中 page_ready_cbfunc / estop_disarm_cbfunc 是定时器回调）。
]]

local ui_app = {}

local SCREEN_W, SCREEN_H = 1024, 600
local IS_PC = rtos.bsp() == "PC"

local data_app = require "data_app"
local ui_vars = require "ui_vars"

local xml = nil
local cur_page = ""
local flow_frame = 0
local flow_ids = { "flow0", "flow1", "flow2" }
local estop_arm = false
local estop_timer = nil
local warned = {}

-- 图片必须与 main.xml 同目录：真机平铺在 /luadb，PC 模拟器同样落到 /luadb
local XML_CANDIDATES = { "/luadb/main.xml", "/res/main.xml", "/main.xml" }

-- ==================== 小工具 ====================

local function warn_once(key, msg, extra)
    if warned[key] then return end
    warned[key] = true
    log.warn("ui", msg, extra)
end

--[[ 取当前页组件；页面切换后旧句柄会失效，所以每次都现取 ]]
local function node(id)
    if not xml then return nil end
    local ok, o = pcall(xml.find, xml, cur_page, id)
    if ok then return o end
    return nil
end

--[[ 保守调用：PLCUI 里越界是返回 nil, err，类型错是抛 error，两种都兜住 ]]
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

local function set_text_if(id, text)
    local o = node(id)
    if o then try(o.set_text, "set_text", o, text) end
end

--[[ 角度按 0.1 度传（set_rotation 的单位是十分之一度） ]]
local function set_angle(o, deg)
    try(o.set_rotation, "set_rotation", o, math.floor(deg * 10 + 0.5))
end

-- ==================== 绑定表刷数 ====================

local function apply_bind(b, v)
    local o = node(b.id)
    if not o or v == nil then return end
    local kind = b.kind

    if kind == "text" then
        try(o.set_text, "set_text", o, tostring(v))
    elseif kind == "src" then
        try(o.set_src, "set_src", o, tostring(v))
    elseif kind == "checked" then
        try(o.set_checked, "set_checked", o, v == true)
    elseif kind == "disabled" then
        try(o.set_disabled, "set_disabled", o, v == true)
    elseif kind == "hidden_invert" then
        -- 变量为真时显示：急停旗标
        try(o.set_hidden, "set_hidden", o, not v)
    elseif kind == "badge_hidden" then
        local n = tonumber(v) or 0
        try(o.set_hidden, "set_hidden", o, n <= 0)
        if n <= 0 then
            local t = node("tab_num")
            if t then try(t.set_hidden, "set_hidden", t, true) end
        end
    elseif kind == "size" then
        try(o.set_size, "set_size", o, math.floor(tonumber(v) or 0), b.h or 6)
    elseif kind == "angle" then
        set_angle(o, tonumber(v) or 0)
    elseif kind == "slider" then
        try(o.set_value, "set_value", o, math.floor(tonumber(v) or 0))
    elseif kind == "state_color" then
        local color = ui_vars.STATE_COLOR[tostring(v)] or "#e9edee"
        -- 文字与颜色一起刷新；个别固件没有 set_color 就只刷文字
        try(o.set_color, "set_color", o, color)
        try(o.set_text, "set_text", o, tostring(v))
    elseif kind == "level_color" then
        local color = ui_vars.LEVEL_COLOR[tostring(v)] or "#e8eef0"
        try(o.set_color, "set_color", o, color)
        try(o.set_text, "set_text", o, tostring(v))
    end
    -- textarea 不参与周期刷新，避免把用户正在输入的内容冲掉
end

--[[ 页签选中态：只认当前页 ]]
local function sync_tabs()
    local tabs = ui_vars.TABS
    for i = 1, #tabs do
        local o = node(tabs[i].id)
        if o then
            try(o.set_checked, "set_checked", o, tabs[i].page == cur_page)
        end
    end
end

--[[ 曲线：整条原子替换，点数必须等于 point-count ]]
local function refresh_charts(v)
    if cur_page == "overview" then
        local c = node("ch_ov")
        if c then
            try(c.set_values, "set_values", c, "t", v.ch_ov_t)
            try(c.set_values, "set_values", c, "p", v.ch_ov_p)
            try(c.set_values, "set_values", c, "s", v.ch_ov_s)
        end
    elseif cur_page == "trend" then
        local c = node("ch_tr")
        if c then
            try(c.set_values, "set_values", c, "t", v.ch_tr_t)
            try(c.set_values, "set_values", c, "p", v.ch_tr_p)
            try(c.set_values, "set_values", c, "s", v.ch_tr_s)
        end
    end
end

--[[ 报警表：rows 含表头，逐格写；单元格文本 ≤ 511 字节 ]]
local function refresh_alarm_table()
    local tb = node("tb_al")
    if not tb then return end
    local rows = data_app.alarm_rows()
    for r = 1, #rows do
        for c = 1, 6 do
            local txt = rows[r][c] or ""
            try(tb.set_cell, "set_cell", tb, r, c, txt)
        end
    end
end

--[[ 参数框：只在进页面或提交/取消后回写 ]]
local function refresh_param_boxes()
    local ids = { "p1", "p2", "p3", "p4", "p5", "p6" }
    for i = 1, #ids do
        local o = node(ids[i])
        if o then
            try(o.set_text, "set_text", o, data_app.param_text(ids[i]))
        end
    end
end

--[[ 负载条颜色与确认键禁用：这两项不是文本也不是尺寸，单独处理 ]]
local function refresh_overview_extras(v)
    for i = 0, 2 do
        local bar = node("bar" .. i)
        if bar then try(bar.set_src, "set_src", bar, v["barc" .. i]) end
        local ak = node("ak" .. i)
        if ak then try(ak.set_disabled, "set_disabled", ak, v["akd" .. i] == true) end
    end
end

-- ==================== 对外：加载与切页 ====================

--[[ plcui.init 兼容新旧固件：新签名是表，老签名是宽高两个参数 ]]
local function plcui_init()
    local errors = {}
    local ok1, ret1, err1 = pcall(plcui.init, { width = SCREEN_W, height = SCREEN_H })
    if ok1 and ret1 then
        return true, "init({width,height})"
    end
    errors[#errors + 1] = "init(table):" .. tostring(ok1 and err1 or ret1)

    local ok2, ret2, err2 = pcall(plcui.init, SCREEN_W, SCREEN_H)
    if ok2 and ret2 then
        return true, "init(w,h)"
    end
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
            -- 错误表里带 attribute / line / col，务必一起打出来：
            -- 光看 "Integer attribute is invalid or out of range" 找不到是哪个属性
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
    log.error("ui", "找不到 main.xml：检查 /luadb/main.xml")
    return nil
end

--[[ 载入界面：init → load → 进首页并刷一次 ]]
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
    estop_arm = false
    local o = node("btn_estop")
    if o then try(o.set_checked, "set_checked", o, false) end
    sys.timerStart(ui_app.page_ready_cbfunc, 40)
    return true
end

--[[ 刷新当前页：绑定表 + 曲线 + 表格 + 页签 + 负载条配色 ]]
function ui_app.refresh()
    if not xml then return end
    local v = data_app.get()

    local list = ui_vars.bind_list(cur_page)
    for i = 1, #list do
        apply_bind(list[i], v[list[i].var])
    end

    if cur_page == "overview" then
        refresh_charts(v)
        refresh_overview_extras(v)
    elseif cur_page == "trend" then
        refresh_charts(v)
    elseif cur_page == "alarm" then
        refresh_alarm_table()
    elseif cur_page == "settings" then
        refresh_param_boxes()
    end

    sync_tabs()
    pcall(plcui.refresh)
end

--[[ 流动条纹：4 帧循环换图，停机时停在第一帧 ]]
function ui_app.tick_flow()
    if not xml then return end
    if data_app.get().running then
        flow_frame = (flow_frame + 1) % 4
    else
        flow_frame = 0
    end
    for i = 1, #flow_ids do
        local o = node(flow_ids[i])
        if o then try(o.set_src, "set_src", o, "flow_" .. flow_frame) end
    end
end

--[[ 给外部模块用的当前页 ]]
function ui_app.current_page()
    return cur_page
end

-- ==================== 事件表 ====================

local H = {}

function H.go_overview()
    ui_app.show("overview")
end

function H.go_trend()
    ui_app.show("trend")
end

function H.go_alarm()
    ui_app.show("alarm")
end

function H.go_settings()
    ui_app.show("settings")
end

function H.line_start()
    data_app.cmd_start()
    estop_arm = false
    local o = node("btn_estop")
    if o then try(o.set_checked, "set_checked", o, false) end
    ui_app.refresh()
end

function H.line_stop()
    data_app.cmd_stop()
    ui_app.refresh()
end

function H.line_reset()
    data_app.cmd_reset()
    estop_arm = false
    local o = node("btn_estop")
    if o then try(o.set_checked, "set_checked", o, false) end
    ui_app.refresh()
end

--[[ 急停解除定时的回调 ]]
function ui_app.estop_disarm_cbfunc()
    estop_arm = false
    local o = node("btn_estop")
    if o then try(o.set_checked, "set_checked", o, false) end
    ui_app.refresh()
end

--[[ 急停：第一下进入待确认，5 秒内第二下才停机 ]]
function H.line_estop()
    if not estop_arm then
        estop_arm = true
        local o = node("btn_estop")
        if o then try(o.set_checked, "set_checked", o, true) end
        set_text_if("status_text", "急停待确认")
        if estop_timer then sys.timerStop(estop_timer) end
        estop_timer = sys.timerStart(ui_app.estop_disarm_cbfunc, 5000)
        log.info("ui", "急停待确认，5 秒内再按一次执行")
        return
    end
    if estop_timer then
        sys.timerStop(estop_timer)
        estop_timer = nil
    end
    estop_arm = false
    data_app.cmd_estop()
    ui_app.refresh()
end

function H.dev_sel0()
    data_app.select_device(0)
    ui_app.refresh()
end

function H.dev_sel1()
    data_app.select_device(1)
    ui_app.refresh()
end

function H.dev_sel2()
    data_app.select_device(2)
    ui_app.refresh()
end

function H.ack0()
    data_app.ack_one(0)
    ui_app.refresh()
end

function H.ack1()
    data_app.ack_one(1)
    ui_app.refresh()
end

function H.ack2()
    data_app.ack_one(2)
    ui_app.refresh()
end

function H.alarm_ack_all()
    data_app.ack_all()
    ui_app.refresh()
end

function H.alarm_clear()
    data_app.clear_acked()
    ui_app.refresh()
end

function H.param_save()
    data_app.commit_params()
    ui_app.refresh()
end

function H.sw1()
    data_app.toggle_sw(1)
    ui_app.refresh()
end

function H.sw2()
    data_app.toggle_sw(2)
    ui_app.refresh()
end

function H.sw3()
    data_app.toggle_sw(3)
    ui_app.refresh()
end

--[[ 滑块：拖动过程与松手都会进这里，只取整不弹提示 ]]
function H.sp_change(ev)
    local v = nil
    if type(ev) == "table" then
        v = ev.value or tonumber(ev.text)
    end
    if v == nil then return end
    data_app.set_setpoint(v)
    ui_app.refresh()
end

function H.bright_change(ev)
    local v = nil
    if type(ev) == "table" then
        v = ev.value or tonumber(ev.text)
    end
    if v == nil then return end
    data_app.set_bright(v)
    ui_app.refresh()
end

--[[ 参数确认：越界不落盘，界面回到旧值 ]]
function H.param_submit(ev)
    local id = type(ev) == "table" and ev.id or nil
    local text = type(ev) == "table" and ev.text or nil
    if not id then return end
    local ok = data_app.set_param(id, tonumber(text))
    refresh_param_boxes()
    ui_app.refresh()
    if not ok then
        log.warn("ui", "参数写入被拒", id, tostring(text))
    end
end

--[[ 参数取消：回滚到上次落盘的值 ]]
function H.param_cancel(ev)
    local id = type(ev) == "table" and ev.id or nil
    if id then
        local o = node(id)
        if o then try(o.set_text, "set_text", o, data_app.param_text(id)) end
    end
    ui_app.refresh()
end

ui_app.handlers = H

return ui_app
