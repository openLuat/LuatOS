--[[
@module  main
@summary 饮料灌装产线中控屏（plcui 6 页界面，Air8607 10 寸 1024x600）
@version 1.0.0
@date    2026.11.11
@board   Air8607（Air1603）+ 10 寸 RGB 1024x600 + GT911 电容触摸

界面素材与布局见 main.xml（由 web/*.html 通过 tools/export_assets.py 导出），
本文件只负责板级初始化、页面切换和业务数据刷新。
]]

PROJECT = "plcui_beverage_line"
VERSION = "1.0.0"


-- 屏幕尺寸常量：H 不能叫 H，会与下方事件表 H 冲突（遮蔽后 height 就成了 table）
local SCREEN_W, SCREEN_H = 1024, 600
local IS_PC = rtos.bsp() == "PC"

local xml           -- plcui 界面实例
local page = "overview"   -- 当前页面 ID

-- ==================== 业务数据（演示用模拟量） ====================

local st = {
    running = true,
    power = true,                 -- 电源开关（btn_power 的亮/暗两态）
    clock = 10 * 3600 + 30 * 60,   -- 10:30:00 起走的模拟时钟（秒）
    dev = { 2.90, 8.30, 3.00, 1.70, 1.50, 2.90, 1.50, 1.20, 1.50, 1.20 },
    rpm = 830, torque = "4.2", level = 68, cap = 64,
    fill_speed = 120, fill_temp = 85,
    torque_now = "4.2N·m", torque_set = "4.2N·m",
    raw_level = 78, label_stock = 71,
    total = 28640, pass_rate = 99.72, bad = 79, oee = 86,
    alarm_pending = 2,
    sound = true, popup = true,
    perm = true, locked = true,
    engineer = false,
    line = "运行中",
    phase = 0,
}

-- 10 台设备节拍（列表里跟随运行状态小幅波动）
local dev_base = { 2.90, 8.30, 3.00, 1.70, 1.50, 2.90, 1.50, 1.20, 1.50, 1.20 }

-- 趋势曲线缓存（与 XML 的 point-count 一致）
local TREND_POINTS = 25
local trend = { level = {}, pressure = {}, speed = {}, temp = {} }
local mini = { cap = {} }

local function seed_series(dst, n, base, amp, phase)
    for i = 1, n do
        dst[i] = base + amp * math.sin(i / 6 + phase)
    end
end

-- ==================== 参数（第 3 页） ====================

local params = {
    p_fill = 500, p_speed = 420, p_vac_time = 1.2, p_vac = 0.35,
    p_wash_temp = 85, p_wash_time = 15, p_wash_chem = 2.0,
    p_torque = 4.2, p_torque_max = 4.2, p_cap_speed = 120,
}
local param_fmt = {
    p_fill = "%.0f", p_speed = "%.0f", p_vac_time = "%.1f", p_vac = "%.2f",
    p_wash_temp = "%.0f", p_wash_time = "%.0f", p_wash_chem = "%.1f",
    p_torque = "%.1f", p_torque_max = "%.1f", p_cap_speed = "%.0f",
}
local param_name = {
    p_fill = "灌装量", p_speed = "灌装速度", p_vac_time = "抽真空时间", p_vac = "真空度",
    p_wash_temp = "水温", p_wash_time = "清洗时间", p_wash_chem = "清洗剂配比",
    p_torque = "旋盖扭矩", p_torque_max = "扭矩上限", p_cap_speed = "旋盖速度",
}
local param_limit = {
    p_fill = { 100, 1500 }, p_speed = { 60, 900 }, p_vac_time = { 0.2, 9.9 }, p_vac = { 0.05, 0.9 },
    p_wash_temp = { 30, 95 }, p_wash_time = { 3, 60 }, p_wash_chem = { 0.1, 9.9 },
    p_torque = { 0.5, 9.9 }, p_torque_max = { 0.5, 9.9 }, p_cap_speed = { 30, 300 },
}

-- 第 2 页设备表（与 XML 初始内容一致，运行时长会累加）
local devices = {
    { "空瓶卸垛机", 428 * 3600 + 20 * 60 }, { "洗瓶机", 420 * 3600 + 10 * 60 },
    { "瓶身检测机", 402 * 3600 + 30 * 60 }, { "灌装机", 428 * 3600 },
    { "旋盖机", 396 * 3600 + 40 * 60 }, { "贴标机", 418 * 3600 },
    { "喷标机", 410 * 3600 + 10 * 60 }, { "喷码机", 386 * 3600 + 50 * 60 },
    { "装箱机", 428 * 3600 }, { "码垛机", 428 * 3600 },
    { "吹瓶机", 421 * 3600 }, { "套标机", 388 * 3600 },
    { "裹包机", 428 * 3600 }, { "AGV 转车", 264 * 3600 },
}

local tree_sel = 11

-- ==================== 通用界面工具 ====================

local function find(id)
    return xml:find(page, id)
end

local function set_text(id, text)
    local o = find(id)
    if o then o:set_text(text) end
end

local function set_checked(id, on)
    local o = find(id)
    if o then o:set_checked(on) end
end

-- 只对当前页存在的 feedback 标签写提示
local function fb(text)
    local o = find("feedback")
    if o then o:set_text(text) end
end

local function clock_text()
    local t = st.clock % 86400
    return string.format("2025-11-11 %02d:%02d:%02d", t // 3600, (t % 3600) // 60, t % 60)
end

local function hms(seconds)
    return string.format("%d:%02d:%02d", seconds // 3600, (seconds % 3600) // 60, seconds % 60)
end

-- ==================== 各页面刷新 ====================

local function refresh_overview()
    set_text("clock", clock_text())
    set_text("k_out", st.total .. "瓶")
    set_text("k_speed", st.fill_speed .. "瓶/分钟")
    set_text("k_pass", string.format("%.2f%%", st.pass_rate))
    if st.running then
        set_text("s1", "运行") set_text("s2", "运行")
        set_text("s5", "运行")
    else
        set_text("s1", "停机") set_text("s2", "停机")
        set_text("s5", "停机")
    end
end

local function refresh_realtime()
    set_text("clock", clock_text())
    for i = 1, 10 do
        set_text("dev" .. (i - 1), string.format("%.2f", st.dev[i]))
    end
    set_text("gauge_rpm", tostring(st.rpm))
    set_text("gauge_torque", st.torque)
    set_text("gauge_level", st.level .. "%")
    set_text("gauge_cap", st.cap .. "%")
    set_text("fill_speed", st.fill_speed .. "瓶/分钟")
    set_text("fill_temp", st.fill_temp .. "℃")
    set_text("torque_now", st.torque_now)
    set_text("torque_set", st.torque_set)
    set_text("raw_level", st.raw_level .. "%")
    set_text("label_stock", st.label_stock .. "%")

    local c = find("trend")
    if c then
        c:set_values("level", trend.level)
        c:set_values("pressure", trend.pressure)
        c:set_values("speed", trend.speed)
        c:set_values("temp", trend.temp)
    end
    local m = find("mini_trend")
    if m then m:set_values("cap", mini.cap) end
end

-- 设备树 tree_1 是“包装设备”分组，tree_2 起才对应 devices 列表
local function tree_device(i)
    local di = i - 1
    if di >= 1 and di <= #devices then return devices[di] end
    return nil
end

local function refresh_assets()
    set_text("clock", clock_text())
    -- 设备表第 i 行的运行时长是独立 label（r<i>_t），第 i 行对应 devices[i]
    for i = 1, #devices do
        set_text("r" .. (i - 1) .. "_t", hms(devices[i][2]))
    end
    local dev = tree_device(tree_sel)
    set_text("d_runtime", dev and hms(dev[2]) or "--")
    set_text("d_session", "6小时12分")
    set_text("d_count", st.total .. "次")
    set_text("d_fault", "2次")
    set_text("d_advice", "正常")
    fb("选中设备：" .. (dev and dev[1] or "包装设备"))
end

local function refresh_params()
    set_text("clock", clock_text())
    for id, v in pairs(params) do
        local o = find(id)
        if o then o:set_text(string.format(param_fmt[id], v)) end
    end
    set_text("cur_user", st.engineer and "工程师" or "操作员")
    set_text("perm_text", st.perm and "已开启" or "关闭")
    set_text("lock_text", st.locked and "已开启" or "关闭")
    fb(st.locked and "参数已锁定，工程师权限可修改" or "参数可编辑，修改后请保存")
end

local function refresh_report()
    set_text("clock", clock_text())
    set_text("k_total", st.total .. "瓶")
    set_text("k_speed", st.fill_speed .. "瓶/分钟")
    set_text("k_pass", string.format("%.2f%%", st.pass_rate))
    set_text("k_bad", st.bad .. "瓶")
end

local function refresh_alarm()
    set_text("clock", clock_text())
    set_text("a_dev", "旋盖机")
    set_text("a_code", "CAPP-012")
    set_text("a_hint", string.format("共 6 条报警，%d 条待处理", st.alarm_pending))
end

local REFRESH = {
    overview = refresh_overview,
    realtime = refresh_realtime,
    assets = refresh_assets,
    params = refresh_params,
    report = refresh_report,
    alarm = refresh_alarm,
}

-- 切页：回调里调用会延后执行，所以切页后延时刷新一次
local function show(target)
    if page == target then return end
    if not xml:show(target) then
        log.warn("ui", "切页失败", target)
        return
    end
    page = target
    sys.timerStart(function()
        if page == target then REFRESH[target]() end
    end, 40)
end

-- ==================== 事件处理 ====================

local H = {}

-- 6 个页面互跳
H.show_overview = function() show("overview") end
H.show_realtime = function() show("realtime") end
H.show_assets = function() show("assets") end
H.show_params = function() show("params") end
H.show_report = function() show("report") end
H.show_alarm = function() show("alarm") end

-- ---------- 第 1 页：实时数据监控 ----------
H.on_refresh = function()
    st.phase = 0
    refresh_realtime()
    fb("曲线已刷新 " .. clock_text())
end

H.on_alarm_ack = function()
    st.alarm_pending = 0
    fb("报警已确认，待处理 0 条")
end

-- ---------- 第 2 页：设备运行管理 ----------
local function select_tree(i)
    tree_sel = i
    set_checked("tree_" .. i, true)
    for n = 1, 11 do
        if n ~= i then set_checked("tree_" .. n, false) end
    end
    local dev = tree_device(i)
    if dev then
        set_text("d_runtime", hms(dev[2]))
        set_text("d_advice", "正常")
        fb("选中设备：" .. dev[1] .. "　运行时长：" .. hms(dev[2]))
    else
        fb("包装设备：共 5 台，全部运行")
    end
end

H.tree_root1 = function() fb("预处理设备：共 3 台，2 台运行") end
H.tree_root2 = function() fb("灌装设备：共 14 台，12 台运行") end
for i = 1, 11 do
    H["tree_" .. i] = function() select_tree(i) end
end

H.tab_dev = function()
    set_checked("tab_dev", true) set_checked("tab_grp", false)
    fb("按设备名排序")
end

H.tab_grp = function()
    set_checked("tab_dev", false) set_checked("tab_grp", true)
    fb("按设备组显示")
end

H.on_start = function()
    st.running = true
    local dev = tree_device(tree_sel)
    fb("已下发启动指令：" .. (dev and dev[1] or "包装设备"))
end

H.on_stop = function()
    st.running = false
    local dev = tree_device(tree_sel)
    fb("已下发停止指令：" .. (dev and dev[1] or "包装设备"))
end

H.on_log = function()
    fb("维修记录：最近 3 次保养均由工程师确认")
end

H.on_engineer = function()
    st.engineer = not st.engineer
    set_checked("btn_eng", st.engineer)
    fb(st.engineer and "工程师权限已开启" or "已退出工程师权限")
end

-- ---------- 第 3 页：工艺参数配置 ----------
for i = 1, 5 do
    H["cat_" .. i] = function()
        for n = 1, 5 do set_checked("cat_" .. n, n == i) end
        local names = { "灌装参数", "洗瓶参数", "旋盖参数", "贴标参数", "喷码参数" }
        fb("当前分类：" .. names[i])
    end
end

H.param_submit = function(ev)
    local id = ev.id
    local value = tonumber(ev.text)
    local limit = param_limit[id]
    if not st.perm then
        fb("修改权限未开启，无法保存参数")
    elseif st.locked then
        fb("参数已锁定，请先解锁")
    elseif value and limit and value >= limit[1] and value <= limit[2] then
        params[id] = value
        fb(string.format("%s 已修改为 %s", param_name[id], ev.text))
    else
        local old = find(id)
        if old then old:set_text(string.format(param_fmt[id], params[id])) end
        if limit then
            fb(string.format("%s 超出范围（%s ~ %s）", param_name[id],
                             string.format(param_fmt[id], limit[1]),
                             string.format(param_fmt[id], limit[2])))
        else
            fb("输入无效")
        end
    end
end

H.param_cancel = function() fb("已取消本次修改") end

H.on_perm = function()
    st.perm = not st.perm
    set_text("perm_text", st.perm and "已开启" or "关闭")
    fb(st.perm and "修改权限已开启" or "修改权限已关闭")
end

H.on_lock = function()
    st.locked = not st.locked
    set_text("lock_text", st.locked and "已开启" or "关闭")
    fb(st.locked and "参数已锁定" or "参数已解锁")
end

H.on_lock_param = function()
    st.locked = true
    set_text("lock_text", "已开启")
    fb("参数已锁定")
end

H.on_save = function()
    if st.locked then fb("参数已锁定，请先解锁") return end
    fb("配置已保存并下发，立即生效")
    log.info("ui", "save params", params.p_fill, params.p_speed, params.p_torque)
end

H.on_drift = function()
    fb("漂移参数已还原到上一版")
end

H.on_default = function()
    params.p_fill, params.p_speed, params.p_vac_time, params.p_vac = 500, 420, 1.2, 0.35
    params.p_wash_temp, params.p_wash_time, params.p_wash_chem = 85, 15, 2.0
    params.p_torque, params.p_torque_max, params.p_cap_speed = 4.2, 4.2, 120
    refresh_params()
    fb("已恢复出厂默认参数")
end

H.on_plog = function()
    fb("修改日志：10:12 灌装量 500→500；09:40 水温 84→85")
end

-- ---------- 第 4 页：产量统计报表 ----------
for i = 1, 6 do
    H["rp_" .. i] = function()
        for n = 1, 6 do set_checked("rp_" .. n, n == i) end
        local names = { "日报", "周报", "月报", "年报", "班次对比", "产品统计" }
        fb("当前报表：" .. names[i])
    end
end

H.on_excel = function() fb("报表已导出 Excel，保存在 /sd/report.xlsx") end
H.on_print = function() fb("打印任务已提交") end
H.on_pdf = function() fb("报表已导出 PDF，保存在 /sd/report.pdf") end
H.on_mail = function() fb("报表已推送到班组长邮箱") end

-- ---------- 第 5 页：故障报警记录 ----------
local function select_tab(id)
    for _, n in ipairs({ "tab_all", "tab_urgent", "tab_warn", "tab_tip" }) do
        set_checked(n, n == id)
    end
end

H.tab_all = function() select_tab("tab_all") fb("显示全部报警") end
H.tab_urgent = function() select_tab("tab_urgent") fb("仅显示紧急报警") end
H.tab_warn = function() select_tab("tab_warn") fb("仅显示警告报警") end
H.tab_tip = function() select_tab("tab_tip") fb("仅显示提示信息") end
for i = 1, 4 do
    H["flt_" .. i] = function()
        for n = 1, 4 do set_checked("flt_" .. n, n == i) end
        local names = { "灌装机", "旋盖机", "贴标机", "装箱机" }
        fb("设备过滤：" .. names[i])
    end
end

H.on_ack = function()
    st.alarm_pending = 0
    set_text("a_hint", "共 6 条报警，0 条待处理")
    fb("选中报警已确认")
end

H.on_reset = function() fb("故障已复位，等待设备反馈") end
-- 「导出」在第一页导出趋势曲线，在第五页导出报警记录
H.on_export = function()
    if page == "realtime" then
        fb("趋势曲线已导出（CSV，含 4 条曲线）")
        log.info("ui", "export trend csv")
    else
        fb("报警记录已导出，共 6 条")
    end
end

H.on_sound = function()
    st.sound = not st.sound
    set_checked("btn_sound", st.sound)
    fb(st.sound and "报警声音已开启" or "报警声音已关闭")
end

H.on_popup = function()
    st.popup = not st.popup
    set_checked("btn_popup", st.popup)
    fb(st.popup and "弹窗提示已开启" or "弹窗提示已关闭")
end

-- ---------- 第 6 页：产线总览 ----------
H.on_login = function()
    st.engineer = not st.engineer
    fb(st.engineer and "工程师已登录（OP01）" or "已退出登录")
end

H.on_power = function()
    st.power = not st.power
    st.running = st.power
    st.line = st.power and "运行中" or "已断电"
    set_checked("btn_power", not st.power)  -- 断电时切到暗红态
    fb(st.power and "系统上电，产线投入运行" or "系统已断电，产线停止")
end

H.on_estop = function()
    st.running = false
    st.line = "急停"
    fb("急停已触发，全线停止运行")
    log.warn("ui", "emergency stop")
end

H.on_line_start = function()
    st.running = true
    st.line = "运行中"
    fb("产线已启动：空瓶卸垛机 → 装箱机 全部就绪")
end

H.on_line_pause = function()
    st.running = false
    st.line = "暂停"
    fb("产线已暂停，设备保持当前状态")
end

H.on_alarm = function()
    st.alarm_pending = st.alarm_pending + 1
    fb("一键报警已上报，等待值班工程师处理")
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

-- 显示初始化走 demo（FactoryHMI/plcui）已验证的 exd_air8607_rgb 扩展库：
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
    if display and display.getSize then
        local w, h = display.getSize()
        log.info("ui", "显示尺寸", tostring(w) .. "x" .. tostring(h))
        if w ~= SCREEN_W or h ~= SCREEN_H then
            log.warn("ui", "显示尺寸与设计稿不一致", tostring(w) .. "x" .. tostring(h),
                "设计稿", SCREEN_W .. "x" .. SCREEN_H)
        end
    end
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

-- 图片必须与 main.xml 同目录（plcui 只接受相对 XML 目录的 src）。
-- 真机：main.xml + 全部图片与脚本一起烧进 /luadb（源码组织在 code/res/，打包时平铺）；
-- PC 模拟器：直接把 code/ 交给模拟器，romfs 平铺后同样走 /luadb 分支。
local XML_CANDIDATES = { "/luadb/main.xml", "/res/main.xml", "/main.xml" }

-- 新版 plcui.init(options)，旧固件是 plcui.init(width, height)。
-- 两种签名的失败原因都会记下来，避免只看到第一个错误掩盖真相。
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

local function init_trend()
    seed_series(trend.level, TREND_POINTS, 74, 22, 0)
    seed_series(trend.pressure, TREND_POINTS, 76, 20, 1.0)
    seed_series(trend.speed, TREND_POINTS, 66, 18, 2.0)
    seed_series(trend.temp, TREND_POINTS, 84, 10, 3.0)
    for i = 1, TREND_POINTS do
        trend.level[i] = math.floor(trend.level[i] + 0.5)
        trend.pressure[i] = math.floor(trend.pressure[i] + 0.5)
        trend.speed[i] = math.floor(trend.speed[i] + 0.5)
        trend.temp[i] = math.floor(trend.temp[i] + 0.5)
    end
    seed_series(mini.cap, 16, 70, 12, 0.5)
end

local function push_point(arr, value)
    table.remove(arr, 1)
    arr[#arr + 1] = value
end

-- 每秒推进一次业务数据
local function tick()
    st.clock = st.clock + 1
    st.phase = st.phase + 1
    local t = st.phase

    if st.running then
        st.total = st.total + math.random(4, 9)
        st.bad = st.bad + (math.random(0, 9) == 0 and 1 or 0)
        st.pass_rate = 99.72 + 0.03 * math.sin(t / 9)
        for i = 1, 10 do
            st.dev[i] = dev_base[i] + 0.06 * math.sin(t / 5 + i)
        end
        st.rpm = 820 + math.floor(10 * math.sin(t / 7))
        st.level = 66 + math.floor(4 * math.sin(t / 11))
        st.cap = 63 + math.floor(2 * math.sin(t / 13))
        st.raw_level = 78
        st.label_stock = 71

        push_point(trend.level, math.floor(74 + 22 * math.sin((TREND_POINTS + t) / 6) + 0.5))
        push_point(trend.pressure, math.floor(76 + 20 * math.sin((TREND_POINTS + t) / 6 + 1.0) + 0.5))
        push_point(trend.speed, math.floor(66 + 18 * math.sin((TREND_POINTS + t) / 6 + 2.0) + 0.5))
        push_point(trend.temp, math.floor(84 + 10 * math.sin((TREND_POINTS + t) / 6 + 3.0) + 0.5))
        push_point(mini.cap, math.floor(70 + 12 * math.sin((16 + t) / 5) + 0.5))
    end

    if page == "realtime" then
        local c = find("trend")
        if c then
            c:add_point("level", trend.level[TREND_POINTS])
            c:add_point("pressure", trend.pressure[TREND_POINTS])
            c:add_point("speed", trend.speed[TREND_POINTS])
            c:add_point("temp", trend.temp[TREND_POINTS])
        end
        local m = find("mini_trend")
        if m then m:add_point("cap", mini.cap[16]) end
        set_text("clock", clock_text())
        for i = 1, 10 do
            set_text("dev" .. (i - 1), string.format("%.2f", st.dev[i]))
        end
        set_text("gauge_rpm", tostring(st.rpm))
        set_text("gauge_level", st.level .. "%")
        set_text("gauge_cap", st.cap .. "%")
    elseif page == "overview" then
        set_text("clock", clock_text())
        set_text("k_out", st.total .. "瓶")
        set_text("k_pass", string.format("%.2f%%", st.pass_rate))
    elseif page == "report" then
        set_text("clock", clock_text())
        set_text("k_total", st.total .. "瓶")
        set_text("k_pass", string.format("%.2f%%", st.pass_rate))
        set_text("k_bad", st.bad .. "瓶")
    elseif page == "assets" then
        set_text("clock", clock_text())
        if st.running then
            for i = 1, #devices do
                devices[i][2] = devices[i][2] + 1
                set_text("r" .. (i - 1) .. "_t", hms(devices[i][2]))
            end
        end
    elseif page == "alarm" then
        set_text("clock", clock_text())
    elseif page == "params" then
        set_text("clock", clock_text())
    end
end

sys.taskInit(function()
    if not IS_PC then
        power_on()
        if not display_init() then
            log.error("ui", "显示初始化失败，界面无法启动")
            return
        end
        if not touch_init() then
            log.warn("ui", "触摸初始化失败，按钮将无法点击")
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

    init_trend()
    xml = load_xml()
    if not xml then
        return
    end
    page = "overview"
    refresh_overview()
    touch_bind()
    backlight_on()

    log.info("ui", "饮料灌装产线中控屏已就绪", st.total .. "瓶")
    sys.timerLoopStart(tick, 1000)

    -- 传送带光点动画：8 帧透明 PNG 轮播（plcui 没有移动组件的 API，
    -- 产线的"流动"效果靠定时 set_src 切帧实现；断电/暂停时定格）
    local belt_frame = 0
    sys.timerLoopStart(function()
        if not st.power or not st.running then return end
        local o = find("anim_belt")
        if o then
            belt_frame = (belt_frame + 1) % 8
            o:set_src("anim_belt_" .. belt_frame)
        end
    end, 120)
end)

sys.run()
