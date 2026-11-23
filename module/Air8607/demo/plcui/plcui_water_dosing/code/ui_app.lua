--[[
@module  ui_app
@summary 界面层：PLCUI 加载、按绑定表刷数、事件分派、流动动画
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件把 main.xml 里的组件搬成可操作的界面，自己不存业务数据：
1、ui_app.load       plcui.init + 载入 main.xml + 进首页；
2、ui_app.refresh    把 data_app.get() 的结果按 ui_vars 绑定表刷到当前页；
3、ui_app.tick_flow  自动态 4 帧流动条纹逐帧换图；
4、ui_app.on_event   main.xml 里每个 on-* 都在 handlers 表里注册。
手自动切换用两级按代替网页版的确认弹窗（PLCUI 无模态组件）：第一下进入待确认，
5 秒内第二下才执行，超时自动解除。
本文件的对外接口有 7 个。
]]

local ui_app = {}

local SCREEN_W, SCREEN_H = 1024, 600

local data_app = require "data_app"
local ui_vars = require "ui_vars"

local xml = nil
local cur_page = "main"
local flow_frame = 0
local mode_timer = nil
local warned = {}

local XML_CANDIDATES = { "/luadb/main.xml", "/res/main.xml", "/main.xml" }

-- ==================== 小工具 ====================

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
    local kind = b.kind
    if kind == "text" then
        try(o.set_text, "set_text", o, tostring(v))
    elseif kind == "src" then
        try(o.set_src, "set_src", o, tostring(v))
    elseif kind == "disabled" then
        try(o.set_disabled, "set_disabled", o, v == true)
    elseif kind == "hidden" then
        try(o.set_hidden, "set_hidden", o, v == true)
    elseif kind == "size" then
        -- 输出条：改宽度露出一截（几何更新，1Hz 调用，满足 2.10 节流预算）
        local w = math.floor(tonumber(v) or 0)
        if w < 1 then w = 1 end
        if w > 180 then w = 180 end
        try(o.set_size, "set_size", o, w, b.h or 10)
    end
end

--[[ 状态切换键选中态 ]]
local function sync_switches()
    local st = data_app.get_state()
    for i = 1, #ui_vars.SWITCHES do
        local sw = ui_vars.SWITCHES[i]
        local o = node(sw.id)
        if o then try(o.set_checked, "set_checked", o, sw.state == st) end
    end
end

-- ==================== 对外：加载与刷新 ====================

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
    log.error("ui", "找不到 main.xml：检查 /luadb/main.xml")
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
    cur_page = "main"
    return true
end

function ui_app.refresh()
    if not xml then return end
    local v = data_app.get()
    local list = ui_vars.bind_list()
    for i = 1, #list do
        apply_bind(list[i], v[list[i].var])
    end
    sync_switches()
    pcall(plcui.refresh)
end

--[[ 流动条纹：4 帧循环换图，仅自动态显示 ]]
function ui_app.tick_flow()
    if not xml then return end
    if data_app.get().flow_anim_hidden then return end
    flow_frame = (flow_frame + 1) % 4
    local o = node("flow_anim")
    if o then try(o.set_src, "set_src", o, "flow_a" .. flow_frame) end
end

--[[ 手自动待确认 5 秒超时回调 ]]
function ui_app.mode_disarm_cbfunc()
    if mode_timer then
        sys.timerStop(mode_timer)
        mode_timer = nil
    end
    data_app.disarm_mode()
    ui_app.refresh()
end

-- ==================== 事件表 ====================

local H = {}

function H.to_stop()
    data_app.set_state("stop")
    ui_app.refresh()
end

function H.to_local()
    data_app.set_state("localm")
    ui_app.refresh()
end

function H.to_remote()
    data_app.set_state("remote")
    ui_app.refresh()
end

function H.to_fault()
    data_app.set_state("fault")
    ui_app.refresh()
end

function H.to_maint()
    data_app.set_state("maint")
    ui_app.refresh()
end

function H.ask_auto()
    local armed = data_app.confirm_mode()
    if armed then
        if mode_timer then sys.timerStop(mode_timer) end
        mode_timer = sys.timerStart(ui_app.mode_disarm_cbfunc, 5000)
    elseif mode_timer then
        sys.timerStop(mode_timer)
        mode_timer = nil
    end
    ui_app.refresh()
end

function H.toggle_p1()
    data_app.toggle_dev("p1")
    ui_app.refresh()
end

function H.toggle_p2()
    data_app.toggle_dev("p2")
    ui_app.refresh()
end

function H.toggle_mx()
    data_app.toggle_dev("mx")
    ui_app.refresh()
end

function H.reset_fault()
    data_app.reset_fault()
    ui_app.refresh()
end

ui_app.handlers = H

return ui_app
