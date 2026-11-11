--[[
@module  ui_app
@summary UI 总装应用功能模块（plcui 加载 / 事件注册 / 切页 / 刷新调度）
@version 1.0
@date    2026.11.10
@usage
本文件为 FactoryHMI 的 UI 总装模块，核心业务逻辑为：
1、ui_app.start 加载 main.xml 并把 16 个界面事件注册到 handlers 表，
   全部处理函数都是具名函数，不使用匿名函数和闭包；
2、加载后给 4 个窗口模块绑定 xml 句柄，刷新一次入口页（flow）；
3、启动 1 秒刷新定时器：按 plcui.status().page 只刷新当前页；
   参数页不主动回写输入框，避免打断正在编辑的内容；
4、另启 320ms 定时器驱动工艺页的管道流光；
5、切页统一走 ui_app.switch_page：xml:show 之后延时 30ms 再刷新新页组件
   （回调里的切页会延后执行，马上 find 新页面组件会拿到 nil）；
6、PC 模拟器专用 pc_snapshot_start 逐页截图，方便自动化视觉验证。

对外接口：
1、ui_app.start
2、ui_app.switch_page(page_id)
3、ui_app.delayed_refresh(page_id)
4、ui_app.refresh_timer_cbfunc
5、ui_app.flow_timer_cbfunc
6~20、各界面事件处理函数
]]

local ui_app = {}

local data_sim = require "data_sim"
local topbar = require "topbar"
local flow_win = require "flow_win"
local param_win = require "param_win"
local alarm_win = require "alarm_win"
local trend_win = require "trend_win"

local XML_PATH = "/luadb/main.xml"
local REFRESH_MS = 1000
local FLOW_MS = 320
local SWITCH_DELAY_MS = 30

local xml_handle = nil
local current_page = "flow"
local switch_pending = false
local switch_retry = 0
local SWITCH_RETRY_MAX = 10
local trend_seeded = false

--[[
取当前页 id，plcui 未就绪时返回 flow；
]]
local function now_page()
    local ok, st = pcall(plcui.status)
    if ok and st and st.page then return st.page end
    return current_page
end

--[[
在当前页脚给一条提示（各页提示位不同，分别落到对应窗口模块）；
]]
local function hint_cur(msg)
    local page = now_page()
    if page == "flow" then
        flow_win.hint(msg)
    elseif page == "param" then
        param_win.hint(msg)
    elseif page == "alarm" then
        alarm_win.hint(msg)
    end
end

--[[
按页面刷新动态组件；
]]
local function refresh_page(page, on_switch)
    if page == "flow" then
        flow_win.refresh()
    elseif page == "alarm" then
        alarm_win.refresh()
    elseif page == "trend" then
        if not trend_seeded then
            trend_win.init_values()
            trend_seeded = true
        end
        trend_win.refresh()
    elseif page == "param" then
        -- 只在切入本页时回写输入框，定时刷新不碰，避免打断正在编辑的内容
        if on_switch then param_win.refresh() end
    end
    topbar.refresh(xml_handle, page)
end

--[[
切换页面（带防抖与延时刷新）；

@api ui_app.switch_page(page_id)
@string page_id 目标页面：flow / param / alarm / trend
]]
function ui_app.switch_page(page_id)
    if not xml_handle then return end
    local ok, err = xml_handle:show(page_id)
    if not ok then
        -- 图片解码失败等情况会拒绝切页，这里停在原页面并提示，不往下走
        log.warn("ui_app", "切页失败", page_id,
            err and err.code or "?", err and err.message or "?")
        hint_cur("页面 " .. tostring(page_id) .. " 加载失败")
        return
    end
    current_page = page_id
    switch_pending = true
    switch_retry = 0
    sys.timerStart(ui_app.delayed_refresh, SWITCH_DELAY_MS, page_id)
end

--[[
切页延时刷新（切页请求可能延后到下一轮 UI 才生效）；
]]
function ui_app.delayed_refresh(page_id)
    if plcui.status().page ~= page_id then
        switch_retry = switch_retry + 1
        if switch_retry <= SWITCH_RETRY_MAX then
            sys.timerStart(ui_app.delayed_refresh, SWITCH_DELAY_MS, page_id)
            return
        end
    end
    switch_pending = false
    refresh_page(page_id, true)
end

--[[
1 秒刷新定时器回调；
]]
function ui_app.refresh_timer_cbfunc()
    if not xml_handle then return end
    local page = plcui.status().page
    if not page then return end
    refresh_page(page, false)
end

--[[
320ms 流光定时器回调；
]]
function ui_app.flow_timer_cbfunc()
    if not xml_handle then return end
    flow_win.flow_tick()
end

--[[
当前页脚提示：控件存在性由各窗口模块的 ui_util 兜底；
]]
local function page_hint(msg)
    hint_cur(msg)
end

-- ==================== 导航事件 ====================

function ui_app.on_show_flow(event)
    ui_app.switch_page("flow")
end

function ui_app.on_show_param(event)
    ui_app.switch_page("param")
end

function ui_app.on_show_alarm(event)
    ui_app.switch_page("alarm")
end

function ui_app.on_show_trend(event)
    ui_app.switch_page("trend")
end

-- ==================== 运行控制 ====================

--[[
自动 / 手动模式切换（点顶栏状态胶囊）；
]]
function ui_app.on_toggle_mode(event)
    if data_sim.estop then
        page_hint("急停状态下不可切换模式")
        return
    end
    if data_sim.mode == "auto" then
        data_sim.mode = "manual"
        page_hint("已切到手动模式，可点击设备操作")
    else
        data_sim.mode = "auto"
        page_hint("已切到自动模式")
    end
    topbar.refresh(xml_handle, plcui.status().page)
end

--[[
整线启动；
]]
function ui_app.on_line_start(event)
    if data_sim.estop then
        page_hint("急停未复位，请到「报警」页复位")
        return
    end
    data_sim.running = true
    data_sim.p1 = true
    data_sim.p2 = true
    data_sim.v2 = true
    if data_sim.v1 <= 0 then data_sim.v1 = 64 end
    page_hint("全线启动")
    refresh_page(plcui.status().page)
end

--[[
整线停止；
]]
function ui_app.on_line_stop(event)
    data_sim.running = false
    data_sim.p1 = false
    data_sim.p2 = false
    page_hint("全线停止")
    refresh_page(plcui.status().page)
end

--[[
急停：全线停机并记录 A-000；
]]
function ui_app.on_line_estop(event)
    if data_sim.estop then
        page_hint("急停已处于触发状态")
        return
    end
    data_sim.estop = true
    data_sim.running = false
    data_sim.p1 = false
    data_sim.p2 = false
    data_sim.v2 = false
    data_sim.add_alarm("A-000", "急停按钮被按下 · 全线停机", "crit")
    page_hint("急停已触发")
    refresh_page(plcui.status().page)
end

--[[
KPI 卡点击：温度/压力卡跳参数页，其余跳趋势页；
]]
function ui_app.on_kpi_click(event)
    if event.id == "kp1" or event.id == "kp2" then
        ui_app.switch_page("param")
    else
        ui_app.switch_page("trend")
    end
end

--[[
绑定窗口模块并加载界面；
]]
local function build_handlers()
    return {
        -- 顶栏 / 导航
        toggle_mode = ui_app.on_toggle_mode,
        show_alarm = ui_app.on_show_alarm,
        show_flow = ui_app.on_show_flow,
        show_param = ui_app.on_show_param,
        show_trend = ui_app.on_show_trend,
        -- 运行控制
        line_start = ui_app.on_line_start,
        line_stop = ui_app.on_line_stop,
        line_estop = ui_app.on_line_estop,
        -- 工艺页设备与 KPI
        dev_p101 = flow_win.on_dev_p101,
        dev_fv101 = flow_win.on_dev_fv101,
        dev_p102 = flow_win.on_dev_p102,
        dev_fv102 = flow_win.on_dev_fv102,
        kpi_click = ui_app.on_kpi_click,
        -- 参数页
        param_submit = param_win.on_submit,
        param_cancel = param_win.on_cancel,
        recipe_pick = param_win.on_recipe_pick,
        apply_recipe = param_win.on_apply,
        -- 报警页
        alarm_row = alarm_win.on_row,
        ack_selected = alarm_win.on_ack_selected,
        ack_all = alarm_win.on_ack_all,
        reset_all = alarm_win.on_reset,
    }
end

--[[
加载界面、注册事件、启动刷新调度；

@api ui_app.start()
@return boolean 成功返回 true
]]
function ui_app.start()
    if not plcui or not plcui.load then
        log.error("ui_app", "固件不支持 plcui 库，请烧录带 LUAT_USE_PLCUI 的固件")
        return false
    end

    xml_handle = plcui.load(XML_PATH, {handlers = build_handlers()})
    if not xml_handle then
        log.error("ui_app", "plcui.load 失败", XML_PATH)
        return false
    end
    log.info("ui_app", "界面加载成功", XML_PATH)

    flow_win.bind(xml_handle)
    param_win.bind(xml_handle)
    alarm_win.bind(xml_handle)
    trend_win.bind(xml_handle)

    current_page = "flow"
    refresh_page("flow", true)

    sys.timerLoopStart(ui_app.refresh_timer_cbfunc, REFRESH_MS)
    sys.timerLoopStart(ui_app.flow_timer_cbfunc, FLOW_MS)
    log.info("ui_app", "刷新调度已启动", REFRESH_MS .. "ms", FLOW_MS .. "ms")
    return true
end

-- ==================== PC 模拟器截图序列（仅验证用） ====================

local SHOT_PAGES = {"flow", "param", "alarm", "trend"}
local shot_step = 0

function ui_app.pc_shot_timer_cbfunc()
    shot_step = shot_step + 1
    if shot_step > 8 then
        log.info("ui_app", "截图序列结束")
        return
    end
    if shot_step % 2 == 1 then
        local page_id = SHOT_PAGES[(shot_step + 1) // 2]
        local ok = plcui.snapshot("shot_" .. page_id .. ".bmp")
        log.info("ui_app", "截图", page_id, ok and "成功" or "失败")
    else
        local next_page = SHOT_PAGES[shot_step // 2 + 1]
        if next_page then
            ui_app.switch_page(next_page)
        end
    end
end

function ui_app.pc_snapshot_start()
    shot_step = 0
    sys.timerLoopStart(ui_app.pc_shot_timer_cbfunc, 1200)
    log.info("ui_app", "PC 截图序列已启动")
end

return ui_app
