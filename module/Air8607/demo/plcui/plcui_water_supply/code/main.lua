--[[
@module  main
@summary 无负压变频供水 HMI（plcui 11 页界面，Air8607 10 寸 1024x600）
@version 1.0.0
@date    2026.11.13
@board   Air8607（Air1603）+ 10 寸 RGB 1024x600 + GT911 电容触摸

页面：运行画面(run) / 时段供水(p_time) / 出口设置(p_out) / 入口设置(p_in) /
换泵休眠(p_sleep) / 泵组设置(p_pumps) / 系统设置(p_sys1,p_sys2) /
厂家设置(p_factory) / 菜单(menu) / 故障记录(fault)。
界面素材与布局见 main.xml（由 web/spec.js 经 tools/build_ui.py 生成）；
图片必须与 main.xml 同目录：打包时把 code/assets/ 内全部素材与
main.xml 一起平铺到 /luadb。
本文件负责板级初始化、显示与触摸、页面切换、业务数据模拟与刷新。
]]

PROJECT = "plcui_water_supply"
VERSION = "1.0.0"

local SCREEN_W, SCREEN_H = 1024, 600
local IS_PC = rtos.bsp() == "PC"

local xml           -- plcui 界面实例
local page = "run"  -- 当前页面 ID

-- ==================== 业务数据（模拟变频供水） ====================

local st = {
    running = true,          -- 水泵系统运行
    mode = "auto",           -- auto / manual
    target = 2.00,           -- 目标压力（运行画面 run_t 可改）
    p = 1.87,                -- 出口压力（Mpa）
    f = 46.5,                -- 变频输出（Hz）
    l = 1.2,                 -- 水箱液位（米）
    pumps = { "run", "freq", "freq", "stand", "stand" },  -- 5 台泵三态
    par = {},                -- 输入框通用存储 id -> text
    sw = {},                 -- 时段供水行开关 id -> bool（默认全关）
}

-- 泵位控件 ID（XML 固定，图片/胶囊成对）
local PUMP_IMG = { "pump_img_1", "pump_img_2", "pump_img_3", "pump_img_4", "pump_img_5" }
local PUMP_CHIP = { "pump_chip_1", "pump_chip_2", "pump_chip_3", "pump_chip_4", "pump_chip_5" }
local CHIP_OF = { run = "chip_vfd", freq = "chip_fpwr", stand = "chip_stby" }

-- toggle 开关：id 即资源基名（tog_xxx），状态存 IDS.tog[ev.id]（_a 启用 / _b 屏蔽）

-- 时钟标签前缀（run 页 run_cd/run_ct，表单页 <page>_cd，故障页 ft_cd，菜单页无）
local CLOCK_PREFIX = {
    run = "run", p_time = "p_time", p_out = "p_out", p_in = "p_in",
    p_sleep = "p_sleep", p_pumps = "p_pumps", p_sys1 = "p_sys1",
    p_sys2 = "p_sys2", p_factory = "p_factory", fault = "ft",
}

-- 下拉框选项表（build_ui.py 生成 ui_ids.lua）
local IDS = require "ui_ids"

-- ==================== 通用界面工具 ====================

local function find(id)
    return xml:find(page, id)
end

local function set_text(id, text)
    local o = find(id)
    if o then o:set_text(text) end
end

local function set_src(id, src)
    local o = find(id)
    if o then o:set_src(src) end
end

-- ==================== 各页面刷新 ====================

local function refresh_clock()
    local pre = CLOCK_PREFIX[page]
    if not pre then return end
    set_text(pre .. "_cd", os.date("%Y/%m/%d"))
    set_text(pre .. "_ct", os.date("%H:%M:%S"))
end

local function refresh_pumps()
    for i = 1, 5 do
        local s = st.pumps[i]
        set_src(PUMP_IMG[i], "pump_" .. i .. "_" .. s)
        set_src(PUMP_CHIP[i], CHIP_OF[s])
    end
end

local function refresh_run()
    refresh_clock()
    refresh_pumps()
    set_text("run_p", string.format("%.2f", st.p))
    set_text("run_f", string.format("%.2f", st.f))
    set_text("run_l", string.format("%.2f", st.l))
    set_text("run_t", string.format("%.2f", st.target))
end

local REFRESH = { run = refresh_run }

-- ==================== 页面切换 ====================

local function show(target)
    if not xml:show(target) then
        log.warn("ui", "切页失败", target)
        return
    end
    page = target
    sys.timerStart(function()
        if page ~= target then return end
        if REFRESH[target] then
            REFRESH[target]()
        else
            refresh_clock()
        end
    end, 40)
end

-- ==================== 事件处理 ====================

local H = {}

-- 跳页（menu/strip/nav 全部 go_* 共用一张表）
local GO = {
    go_run = "run", go_menu = "menu", go_flt = "fault",
    go_p_time = "p_time", go_p_out = "p_out", go_p_in = "p_in",
    go_p_sleep = "p_sleep", go_p_pumps = "p_pumps",
    go_p_sys1 = "p_sys1", go_p_sys2 = "p_sys2", go_p_factory = "p_factory",
}
for name, target in pairs(GO) do
    H[name] = function() show(target) end
end

-- ---------- 运行画面：启停 / 自动手动 ----------
H.run_start = function()
    st.running = true
    if st.pumps[1] == "stand" and st.pumps[5] == "stand" then
        st.pumps = { "run", "freq", "freq", "stand", "stand" }  -- 全停后恢复初始组合
    end
    st.p, st.f, st.l = st.target * 0.94, 46.5, 1.2              -- 立即恢复示值，点击即见效
    log.info("ui", "水泵启动")
    if page == "run" then refresh_run() end
end

H.run_stop = function()
    st.running = false
    st.p, st.f, st.l = 0, 0, 0
    st.pumps = { "stand", "stand", "stand", "stand", "stand" }
    log.info("ui", "水泵停止")
    if page == "run" then refresh_run() end
end

H.set_auto = function()
    st.mode = "auto"
    set_src("run_auto", "run_auto_a")
    set_src("run_manual", "run_manual_b")
    log.info("ui", "自动运行")
end

H.set_manual = function()
    st.mode = "manual"
    set_src("run_auto", "run_auto_b")
    set_src("run_manual", "run_manual_a")
    log.info("ui", "手动运行")
end

-- ---------- 时段供水：行开关 ----------
H.sw_click = function(ev)
    local on = not st.sw[ev.id]
    st.sw[ev.id] = on
    set_src(ev.id, on and "sw_on" or "sw_off")
    log.info("ui", "时段开关", ev.id, on and "开" or "关")
end

-- ---------- 表单页：toggle 开关（ev.id 共享处理器） ----------
H.tog_click = function(ev)
    if IDS.tog[ev.id] == nil then return end
    local on = not IDS.tog[ev.id]
    IDS.tog[ev.id] = on
    set_src(ev.id, ev.id .. (on and "_a" or "_b"))
    log.info("ui", "开关", ev.id, on and "启用" or "屏蔽")
end

-- ---------- 表单页：下拉框（点击循环切换选项） ----------
H.sel_click = function(ev)
    local s = IDS.sel[ev.id]
    if not s then return end
    local idx = 1
    for i, v in ipairs(s.opts) do
        if v == s.cur then idx = i break end
    end
    s.cur = s.opts[idx % #s.opts + 1]
    set_text(ev.id .. "L", s.cur)
    log.info("ui", "选项", ev.id, s.cur)
end

-- ---------- 表单页：输入框提交 / 取消 ----------
H.val_submit = function(ev)
    st.par[ev.id] = ev.text
    if ev.id == "run_t" then            -- 目标压力影响运行模拟
        local v = tonumber(ev.text)
        if v and v >= 0 and v <= 2.5 then
            st.target = v
        else
            set_text("run_t", string.format("%.2f", st.target))
            log.warn("ui", "目标压力超范围 0~2.5，已恢复")
            return
        end
    end
    log.info("ui", "参数", ev.id, ev.text)
end

H.val_cancel = function()
    log.info("ui", "取消输入")
end

-- ---------- 表单页：动作按钮（恢复默认/校准/确定/停用） ----------
H.act_click = function(ev)
    local name = ({
        act_reset = "恢复默认参数",
        act_pcal = "压力校准",
        act_off = "工程时间停用",
        act_ok = "时间校准确认",
        act_tcal = "触摸校准",
    })[ev.id]
    log.info("ui", name or ev.id)
end

-- ---------- 故障页：清除故障记录 ----------
H.clear_faults = function()
    local t = find("flt_tbl")
    if t then
        for row = 2, 8 do
            for col = 1, 4 do
                t:set_cell(row, col, "")
            end
        end
    end
    log.info("ui", "故障记录已清除")
end

-- ==================== 模拟引擎 ====================

local tick_t = 0

-- 泵组轮换：三态数组左移一位（run->freq->stand->run）
local function rotate_pumps()
    local first = table.remove(st.pumps, 1)
    st.pumps[5] = first
end

-- 每秒推进业务数据并刷新当前页
local function tick()
    tick_t = tick_t + 1
    refresh_clock()
    if st.running then
        st.p = st.target * 0.94 + 0.05 * math.sin(tick_t / 5)
        st.f = 46.5 + 3.0 * math.sin(tick_t / 7)
        st.l = 1.2 + 0.15 * math.sin(tick_t / 4)
        if IDS.tog.tog_rotate and tick_t % 15 == 0 then   -- 轮换功能启用
            rotate_pumps()
        end
    end
    if page == "run" then refresh_run() end
end

-- ==================== 板级初始化（Air8607） ====================

local BL = { pwm_ch = 3, freq = 1000, duty = 82 }

local function power_on()
    pwm.setup(BL.pwm_ch, BL.freq, 0)
    pwm.start(BL.pwm_ch)
    gpio.setup(17, 0)   -- LCD 供电（低有效）
    gpio.setup(15, 1)   -- DISP
    gpio.setup(73, 0)   -- 功放关断
    i2c.setup(1, i2c.FAST)
    sys.wait(120)
end

-- 显示初始化走 demo 已验证的 exd_air8607_rgb 扩展库：
-- 参数默认即 10 寸 1024x600 RGB，display 后端失败自动降级 lcd 后端
local function display_init()
    if IS_PC then return true end
    local exd = require "exd_air8607_rgb"
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("ui", "显示初始化失败", info)
        return false
    end
    log.info("ui", "显示就绪", type(info) == "string" and info or "display")
    return true
end

local function backlight_on()
    if IS_PC then return end
    pwm.setup(BL.pwm_ch, BL.freq, BL.duty)
    pwm.start(BL.pwm_ch)
    log.info("ui", "背光已点亮", BL.duty .. "%")
end

-- 触摸初始化用 demo 的 tp_app（i2c1 + GT911），可在 plcui.init 之前完成
local function touch_init()
    if IS_PC then return true end
    local tp_app = require "tp_app"
    return tp_app.init()
end

-- plcui.device_bind_touch 必须在 plcui.init 之后调用
local function touch_bind()
    if IS_PC then return end
    local tp_app = require "tp_app"
    if not tp_app.bind() then
        log.error("ui", "触摸绑定 plcui 失败")
    end
end

-- ==================== 界面初始化（兼容新旧固件） ====================

local XML_CANDIDATES = { "/luadb/main.xml", "/res/main.xml", "/main.xml" }

-- 新版 plcui.init(options)，旧固件是 plcui.init(width, height)。
local function plcui_init()
    local errs = {}
    local attempts = {
        { "init({width,height})", function() return plcui.init({ width = SCREEN_W, height = SCREEN_H }) end },
        { "init(w,h)", function() return plcui.init(SCREEN_W, SCREEN_H) end },
    }
    for _, a in ipairs(attempts) do
        local ok, ret, err = pcall(a[2])
        if ok and ret then
            return true, a[1]
        end
        local why = (not ok) and tostring(ret)
            or (type(err) == "table" and (err.message or err.code) or tostring(err))
        errs[#errs + 1] = a[1] .. " -> " .. tostring(why)
    end
    return false, table.concat(errs, " | ")
end

local function load_xml()
    for _, path in ipairs(XML_CANDIDATES) do
        if io.exists(path) then
            local ok, doc, err = pcall(plcui.load, path, { handlers = H })
            if ok and doc then
                log.info("ui", "界面已加载", path)
                return doc
            end
            local reason = err and (err.message or err.code) or tostring(doc)
            log.error("ui", "加载失败", path, reason)
            return nil
        end
    end
    log.error("ui", "找不到 main.xml，请检查 /luadb/main.xml、/res/main.xml 或 /main.xml")
    return nil
end

-- ==================== 主任务 ====================

sys.taskInit(function()
    if not IS_PC then
        power_on()
        if not display_init() then
            return
        end
        if not touch_init() then
            log.error("ui", "触摸初始化失败，请检查 GT911 排线")
            return
        end
    end

    local ok, why = plcui_init()
    if not ok then
        log.error("ui", "plcui.init 失败", why, "请确认固件已开启 LUAT_USE_PLCUI")
        return
    end
    local version = plcui.version and plcui.version() or "?"
    local platform = plcui.status and (plcui.status().platform or "?") or "?"
    log.info("ui", "plcui", version, platform)

    xml = load_xml()
    if not xml then
        return
    end
    page = "run"
    refresh_run()
    touch_bind()
    backlight_on()

    log.info("ui", "供水 HMI 已就绪")
    sys.timerLoopStart(tick, 1000)
end)

sys.run()
