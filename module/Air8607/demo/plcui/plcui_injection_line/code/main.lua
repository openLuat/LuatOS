--[[
@module  main
@summary 注塑产线状态监管 HMI（plcui 5 页界面，Air8607 10 寸 1024x600）
@version 1.0.0
@date    2026.11.11
@board   Air8607（Air1603）+ 10 寸 RGB 1024x600 + GT911 电容触摸

页面：产线总览(ov) / 注塑机监控(mc) / 控制台(ctl) / 参数设定(pr) / 生产记录(rc)。
界面素材与布局见 main.xml（由 web/*.html 通过 tools/export_assets.py 导出），
本文件负责板级初始化、页面切换、业务数据模拟与刷新。
]]

PROJECT = "plcui_injection_line"
VERSION = "1.0.0"

local SCREEN_W, SCREEN_H = 1024, 600
local IS_PC = rtos.bsp() == "PC"

local xml           -- plcui 界面实例
local page = "ov"   -- 当前页面 ID

-- ==================== 业务数据（模拟注塑产线） ====================

-- 6 个工艺阶段时长（秒），合计 32.5s = 一模周期
local PHASE_DUR = { 5.0, 6.0, 8.0, 9.0, 3.0, 1.5 }
local PHASE_NAME = { "合模", "注射", "保压", "冷却", "开模", "顶出" }

-- 8 区温度设定（与参数页输入框初值一致）
local TEMP_DEFAULT = { 210, 215, 220, 215, 225, 45, 120, 45 }
-- 压力/时间参数默认值：注射压力 保压压力 背压 计量转速 冷却时间 开模时间 顶出次数
local PAR_DEFAULT = {
    sp_p1 = 125, sp_p2 = 85, sp_p3 = 60, sp_p4 = 12.5,
    sp_v1 = 86, sp_h1 = 3.5, sp_h2 = 8.5, sp_n1 = 2,
}

local function new_machine(no)
    return {
        name = no,
        shot = 1284,            -- 累计模次
        good = 1276,            -- 合格数
        cyc = 32.5,             -- 周期（s）
        phase = 0,              -- 0..5 工艺阶段
        phase_t = 0,            -- 当前阶段已运行（s）
        tp = { 210, 215, 220, 218, 225, 45 },       -- 6 区实测温度
        sp = { 210, 215, 220, 215, 225, 45, 120, 45 }, -- 8 区设定
        pr = { 125, 85, 12.5, 1286 },               -- 注射压力/保压/背压/锁模力
        clamp = 1286, pos = 48.2, vel = 86, screw = 12.5,
    }
end

local st = {
    clock = 8 * 3600,            -- 08:00:00 起走的模拟时钟（秒）
    date = "2026-11-11",
    running = true,              -- 全线运行
    paused = false,
    mode = 1,                    -- 1 自动 / 2 半自动 / 3 手动
    shift = 1,                   -- 班次 1..3
    sel = 1,                     -- 监控页选中机台（1..3）
    rc = 1,                      -- 参数页选中配方（1..4），勿与 sel 混用
    plan = 4200,
    al_count = 2,                -- 待处理报警
    machines = { new_machine(1), new_machine(2), new_machine(3) },
    -- 单机开关（控制台表格）：true = 设备运行中（按钮显示"停止"）
    aux = {
        im1 = true, im2 = true, im3 = true, rob = true, belt = true,
        dryer = true, chiller = true, moldtemp = true, packer = true, gran = false,
    },
}

-- 单机开关顺序（sw_1..sw_10 的业务键）
local SW_KEYS = { "im1", "im2", "im3", "rob", "belt", "dryer", "chiller",
                  "moldtemp", "packer", "gran" }
local SW_NAME = {
    im1 = "注塑机 1#", im2 = "注塑机 2#", im3 = "注塑机 3#", rob = "桁架机械手",
    belt = "传送带", dryer = "干燥机", chiller = "冷水机", moldtemp = "模温机",
    packer = "称重包装", gran = "粉碎机",
}

-- 条形图控件 -> 动画帧组（bar<槽宽>_<色>，10 档共享帧）
local BAR_GROUP = {
    bar_t1 = "bar230_g", bar_t2 = "bar230_g", bar_t3 = "bar230_g",
    bar_t4 = "bar230_y", bar_t5 = "bar230_g", bar_t6 = "bar230_g",
    bar_p1 = "bar230_o", bar_p2 = "bar230_o", bar_p3 = "bar230_g", bar_p4 = "bar230_g",
    bar_ao1 = "bar170_g", bar_ao2 = "bar170_o", bar_ao3 = "bar170_g", bar_ao4 = "bar170_g",
}

-- 趋势图滚动缓冲（与 XML series 初值衔接）
local trend = {
    t1 = {}, t2 = {}, t5 = {}, p1 = {}, p2 = {},
}

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

local function set_src(id, src)
    local o = find(id)
    if o then o:set_src(src) end
end

-- 条形档位：百分比 -> 0..9 档（帧内容为 (lvl*10+5)% 填充）
local function set_bar(id, pct)
    local group = BAR_GROUP[id]
    if not group then return end
    local lvl = math.floor(pct / 10)
    if lvl < 0 then lvl = 0 end
    if lvl > 9 then lvl = 9 end
    set_src(id, group .. "_" .. lvl)
end

local function clock_hms()
    local t = st.clock % 86400
    return string.format("%02d:%02d:%02d", t // 3600, (t % 3600) // 60, t % 60)
end

local function clock_text()
    return st.date .. " " .. clock_hms()
end

-- ==================== 各页面刷新 ====================

local function machine_total()
    local out = 0
    for i = 1, 3 do out = out + st.machines[i].shot end
    return out
end

local function machine_good()
    local out = 0
    for i = 1, 3 do out = out + st.machines[i].good end
    return out
end

local function refresh_ov()
    set_text("clock", clock_text())
    local out = machine_total()
    local good = machine_good()
    local rate = out / st.plan * 100
    local yield = good / math.max(out, 1) * 100
    set_text("kpi_out", tostring(out))
    set_text("kpi_rate", string.format("%.1f%%", rate))
    set_text("kpi_yield", string.format("%.1f", yield))
    set_text("kpi_oee", string.format("%.1f", 84 + 4 * math.sin(st.clock / 400)))
    set_text("kpi_cyc", string.format("%.1f", st.machines[1].cyc))
    for i = 1, 3 do
        local m = st.machines[i]
        local run = st.running and not st.paused
        set_text("m" .. i .. "st", run and "运行" or "停机")
        set_text("m" .. i .. "shot", "模次 " .. tostring(m.shot))
        set_text("st_m" .. i,
            string.format("%s · %s · 模次 %.0f", m.name, run and "自动" or "待机", m.shot))
    end
    set_text("belt_spd", st.running and "12.5 m/min" or "0.0 m/min")
    set_text("belt_cnt", "班次计数 " .. tostring(out))
    set_text("dry_st", st.aux.dryer and "85℃ 运行" or "待机")
    set_text("cool_st", st.aux.chiller and "23.4℃ 运行" or "待机")
    set_text("pack_st", st.aux.packer and "运行" or "待机")
    if st.al_count > 0 then
        set_text("al_txt", "模温机 3# 温度超限 +2℃（待处理）")
        set_text("al_cnt", tostring(st.al_count))
    else
        set_text("al_txt", "无待处理报警，产线运行正常")
        set_text("al_cnt", "0")
    end
end

local function refresh_mc()
    set_text("clock", clock_text())
    for n = 1, 3 do
        set_checked("sel_m" .. n, n == st.sel)
    end
    local m = st.machines[st.sel]
    local run = st.running and not st.paused
    set_text("mc_st", run and (PHASE_NAME[m.phase + 1] .. "中") or "停机待机")
    set_text("mc_shot", tostring(m.shot))
    set_text("mc_cyc", string.format("%.1f", m.cyc))
    set_text("mc_good", tostring(m.good))
    set_text("mc_clamp", string.format("%.0f", m.clamp))
    set_text("mc_pos", string.format("%.1f", m.pos))
    set_text("mc_vel", string.format("%.0f", m.vel))
    set_text("mc_screw", string.format("%.1f", m.screw))

    -- 工艺阶段条（整条多态帧）+ 周期进度
    set_src("anim_phase", "anim_phase_" .. m.phase)
    local done, total = m.phase_t, 0
    for i = 1, m.phase do done = done + PHASE_DUR[i] end
    for i = 1, 6 do total = total + PHASE_DUR[i] end
    set_text("ph_prog", string.format("%.0f%%", done / total * 100))
    set_text("ph_time", string.format("%.1f s", m.phase_t))

    -- 温度 / 压力：数值 + 条形档位
    for i = 1, 6 do
        set_text("tv_t" .. i, string.format("%.0f / %.0f", m.tp[i], m.sp[i]))
        set_bar("bar_t" .. i, m.tp[i] / math.max(m.sp[i], 1) * 70)
    end
    local pr_max = { 200, 150, 20, 1600 }
    for i = 1, 4 do
        if i == 4 then
            set_text("pv_p4", string.format("%.0f kN", m.pr[4]))
        else
            set_text("pv_p" .. i, string.format("%.1f", m.pr[i]))
        end
        set_bar("bar_p" .. i, m.pr[i] / pr_max[i] * 100)
    end

    -- 趋势图（每秒推 1 点，窗口 25 点）
    local c1 = find("chart_t")
    if c1 then
        c1:set_values("t1", trend.t1)
        c1:set_values("t2", trend.t2)
        c1:set_values("t5", trend.t5)
    end
    local c2 = find("chart_p")
    if c2 then
        c2:set_values("p1", trend.p1)
        c2:set_values("p2", trend.p2)
    end

    set_text("mc_spos", string.format("%.1f mm", m.pos))
    set_text("mc_cush", string.format("%.1f mm", 6.8 + 0.4 * math.sin(st.clock / 20)))
    set_text("mc_dose", string.format("%.1f s", 2.8 + 0.2 * math.sin(st.clock / 30)))
    set_text("mc_rest", string.format("%.1f mm", 8.2 + 0.3 * math.sin(st.clock / 25)))
    set_text("mc_upd", clock_hms())
end

local function refresh_ctl()
    set_text("clock", clock_text())
    set_checked("mode_auto", st.mode == 1)
    set_checked("mode_semi", st.mode == 2)
    set_checked("mode_man", st.mode == 3)
    for i = 1, 10 do
        set_checked("sw_" .. i, st.aux[SW_KEYS[i]])
    end
    local m = st.machines[1]
    set_text("ao1", string.format("%.0f", m.pr[1]))
    set_text("ao2", string.format("%.1f", m.pr[3]))
    set_text("ao3", string.format("%.0f%%", m.vel))
    set_text("ao4", "55%")
    set_bar("bar_ao1", m.pr[1] / 200 * 100)
    set_bar("bar_ao2", m.pr[3] / 20 * 100)
    set_bar("bar_ao3", m.vel)
    set_bar("bar_ao4", 55)
    if st.running and not st.paused then
        set_text("diag1", "I1 电磁阀 24.1V")
        set_text("diag2", "I2 安全门 已闭合")
        set_text("diag3", "Q3 加热 92%")
        set_text("diag4", "注塑周期 " .. string.format("%.1f", m.cyc) .. " s 正常")
    else
        set_text("diag1", "I1 电磁阀 0.0V")
        set_text("diag2", "I2 安全门 已闭合")
        set_text("diag3", "Q3 加热 停止")
        set_text("diag4", st.paused and "产线暂停中" or "产线停止中")
    end
end

-- 参数页：16 个输入框 + 修改历史
local PAR_IDS = { "sp_t1", "sp_t2", "sp_t3", "sp_t4", "sp_t5", "sp_t6", "sp_t7", "sp_t8",
                  "sp_p1", "sp_p2", "sp_p3", "sp_p4", "sp_v1", "sp_h1", "sp_h2", "sp_n1" }
local PAR_FMT = {
    sp_t1 = "%.0f", sp_t2 = "%.0f", sp_t3 = "%.0f", sp_t4 = "%.0f", sp_t5 = "%.0f",
    sp_t6 = "%.0f", sp_t7 = "%.0f", sp_t8 = "%.0f",
    sp_p1 = "%.0f", sp_p2 = "%.0f", sp_p3 = "%.0f", sp_p4 = "%.1f",
    sp_v1 = "%.0f", sp_h1 = "%.1f", sp_h2 = "%.1f", sp_n1 = "%.0f",
}
local PAR_LIMIT = {
    sp_t1 = { 0, 300 }, sp_t2 = { 0, 300 }, sp_t3 = { 0, 300 }, sp_t4 = { 0, 300 },
    sp_t5 = { 0, 300 }, sp_t6 = { 0, 150 }, sp_t7 = { 0, 150 }, sp_t8 = { 0, 150 },
    sp_p1 = { 0, 200 }, sp_p2 = { 0, 150 }, sp_p3 = { 0, 100 }, sp_p4 = { 0, 30 },
    sp_v1 = { 0, 100 }, sp_h1 = { 0, 20 }, sp_h2 = { 0, 30 }, sp_n1 = { 0, 10 },
}
local PAR_NAME = {
    sp_t1 = "料筒 1 区", sp_t2 = "料筒 2 区", sp_t3 = "料筒 3 区", sp_t4 = "料筒 4 区",
    sp_t5 = "喷嘴温度", sp_t6 = "油温", sp_t7 = "干燥温度", sp_t8 = "模温",
    sp_p1 = "注射压力", sp_p2 = "保压压力", sp_p3 = "背压", sp_p4 = "螺杆转速",
    sp_v1 = "注射速度", sp_h1 = "冷却时间", sp_h2 = "开模时间", sp_n1 = "顶出次数",
}

local function refresh_pr()
    set_text("clock", clock_text())
    for n = 1, 4 do
        set_checked("rc_sel" .. n, n == st.rc)
    end
end

local function refresh_rc()
    set_text("clock", clock_text())
    local out = machine_total()
    set_text("st_today", tostring(out))
    set_text("st_hours", string.format("%.1f", (st.clock - 8 * 3600) / 3600))
    set_text("st_stop", tostring(st.mode == 3 and 2 or 1))
    set_text("st_mtbf", tostring(96 + (st.shift - 1) * 12))
end

local REFRESH = {
    ov = refresh_ov, mc = refresh_mc, ctl = refresh_ctl,
    pr = refresh_pr, rc = refresh_rc,
}

-- ==================== 页面切换 ====================

local PAGE_ORDER = { "ov", "mc", "ctl", "pr", "rc" }

local function show(target)
    if not xml:show(target) then
        log.warn("ui", "切页失败", target)
        return
    end
    page = target
    for _, name in ipairs(PAGE_ORDER) do
        set_checked("nav_" .. name, name == target)
    end
    sys.timerStart(function()
        if page == target and REFRESH[target] then REFRESH[target]() end
    end, 40)
end

-- ==================== 事件处理 ====================

local H = {}

-- 底部导航 5 页互跳
H.show_ov = function() show("ov") end
H.show_mc = function() show("mc") end
H.show_ctl = function() show("ctl") end
H.show_pr = function() show("pr") end
H.show_rc = function() show("rc") end

-- ---------- 控制台：启停 / 模式 ----------
H.run_start = function()
    st.running = true
    st.paused = false
    refresh_ctl()
    log.info("ui", "产线启动")
end

H.run_stop = function()
    st.running = false
    st.paused = false
    refresh_ctl()
    log.info("ui", "产线停止")
end

H.run_pause = function()
    st.paused = not st.paused
    refresh_ctl()
end

H.run_reset = function()
    st.al_count = 0
    for i = 1, 3 do
        st.machines[i].phase, st.machines[i].phase_t = 0, 0
    end
    refresh_ctl()
end

local function set_mode(mode)
    st.mode = mode
    set_checked("mode_auto", mode == 1)
    set_checked("mode_semi", mode == 2)
    set_checked("mode_man", mode == 3)
end

H.mode_auto = function() set_mode(1) end
H.mode_semi = function() set_mode(2) end
H.mode_man = function() set_mode(3) end

-- ---------- 控制台：点动（演示只记日志） ----------
H.jog_open = function() log.info("ui", "点动 开模") end
H.jog_close = function() log.info("ui", "点动 合模") end
H.jog_eject = function() log.info("ui", "点动 顶出") end
H.jog_inj = function() log.info("ui", "点动 注射") end
H.jog_feed = function() log.info("ui", "点动 塑化") end
H.jog_rob = function() log.info("ui", "点动 机械手取件") end

-- ---------- 控制台：单机开关（sw_1..sw_10 与 SW_KEYS 一一对应） ----------
local function toggle_sw(key)
    st.aux[key] = not st.aux[key]
    for i = 1, 10 do
        set_checked("sw_" .. i, st.aux[SW_KEYS[i]])
    end
    log.info("ui", SW_NAME[key], st.aux[key] and "启动" or "停止")
end

H.sw_im1 = function() toggle_sw("im1") end
H.sw_im2 = function() toggle_sw("im2") end
H.sw_im3 = function() toggle_sw("im3") end
H.sw_rob = function() toggle_sw("rob") end
H.sw_belt = function() toggle_sw("belt") end
H.sw_dryer = function() toggle_sw("dryer") end
H.sw_chiller = function() toggle_sw("chiller") end
H.sw_moldtemp = function() toggle_sw("moldtemp") end
H.sw_packer = function() toggle_sw("packer") end
H.sw_gran = function() toggle_sw("gran") end

-- ---------- 控制台：班次 / 历史 ----------
H.shift_clear = function()
    for i = 1, 3 do
        st.machines[i].shot, st.machines[i].good = 0, 0
    end
    if page == "ctl" then refresh_ctl() end
end

H.shift_change = function()
    st.shift = st.shift % 3 + 1
    log.info("ui", "切换班次", st.shift)
end

H.his_save = function()
    set_text("par_h3", st.date .. " " .. clock_hms() .. " 操作历史已保存")
end

H.alarm_ack = function()
    st.al_count = 0
    log.info("ui", "报警已确认")
end

H.go_rc = function() show("rc") end

-- ---------- 监控页：机台选择 ----------
local function select_machine(n)
    st.sel = n
    for i = 1, 3 do
        set_checked("sel_m" .. i, i == n)
    end
    refresh_mc()
end

H.sel_m1 = function() select_machine(1) end
H.sel_m2 = function() select_machine(2) end
H.sel_m3 = function() select_machine(3) end

-- ---------- 参数页：输入框提交 / 取消 ----------
local function par_write_back(id)
    local v = tonumber(PAR_DEFAULT[id] or TEMP_DEFAULT[1])
    if id:sub(1, 4) == "sp_t" then
        v = st.machines[1].sp[tonumber(id:sub(5))]
        set_text(id, string.format(PAR_FMT[id], v))
    else
        v = PAR_DEFAULT[id]
        set_text(id, string.format(PAR_FMT[id], v))
    end
end

H.par_submit = function(ev)
    local id = ev.id
    local value = tonumber(ev.text)
    local limit = PAR_LIMIT[id]
    if not limit or not value then
        par_write_back(id)
        set_text("par_h2", "输入无效，已恢复原值")
        return
    end
    if value < limit[1] or value > limit[2] then
        par_write_back(id)
        set_text("par_h2", string.format("%s 超范围 %d~%d，已恢复",
            PAR_NAME[id] or id, limit[1], limit[2]))
        return
    end
    if id:sub(1, 4) == "sp_t" then
        local idx = tonumber(id:sub(5))
        for i = 1, 3 do st.machines[i].sp[idx] = value end
    else
        PAR_DEFAULT[id] = value
    end
    set_text("par_h1", st.date .. " " .. clock_hms() .. " " ..
        (PAR_NAME[id] or id) .. " 改为 " .. ev.text)
    log.info("ui", "参数", id, ev.text)
end

H.par_cancel = function()
    set_text("par_h2", "已取消本次修改")
end

-- ---------- 参数页：配方 / 下发 ----------
local RC_NAME = { "ABS 壳体", "PP 盖板", "PC 透明件", "PA66 结构件" }

local function select_rc(n)
    st.rc = n
    for i = 1, 4 do
        set_checked("rc_sel" .. i, i == n)
    end
    set_text("par_h1", "当前配方：" .. RC_NAME[n])
end

H.rc_sel1 = function() select_rc(1) end
H.rc_sel2 = function() select_rc(2) end
H.rc_sel3 = function() select_rc(3) end
H.rc_sel4 = function() select_rc(4) end

H.par_apply = function()
    set_text("par_h2", "参数已下发，配方 " .. RC_NAME[st.rc] .. " 生效")
end

H.par_def = function()
    for i = 1, 3 do
        for k, v in ipairs(TEMP_DEFAULT) do st.machines[i].sp[k] = v end
    end
    for k, v in pairs(PAR_DEFAULT) do
        if PAR_LIMIT[k] and k ~= "sp_p4" then PAR_DEFAULT[k] = v end
    end
    for _, id in ipairs(PAR_IDS) do par_write_back(id) end
    set_text("par_h3", "已恢复出厂默认参数")
end

H.par_upld = function() set_text("par_h2", "参数已上传：/sd/param_" .. RC_NAME[st.rc] .. ".csv") end
H.par_dnld = function() set_text("par_h2", "配方参数已下载并载入寄存器") end

-- ---------- 记录页：翻页 ----------
H.page_prev = function() log.info("ui", "记录上一页") end
H.page_next = function() log.info("ui", "记录下一页") end

-- ==================== 模拟引擎 ====================

local function seed_trend()
    for i = 1, 25 do
        trend.t1[i] = 210 + 2 * math.sin(i / 3)
        trend.t2[i] = 215 + 2 * math.sin(i / 3 + 1)
        trend.t5[i] = 225 + 2 * math.sin(i / 3 + 2)
        trend.p1[i] = 125 + 8 * math.sin(i / 2)
        trend.p2[i] = 85 + 5 * math.sin(i / 2 + 1)
    end
end

local function push_point(arr, v)
    table.remove(arr, 1)
    arr[#arr + 1] = v
end

-- 每秒推进一次业务数据
local function tick()
    st.clock = st.clock + 1
    local t = st.clock

    for i = 1, 3 do
        local m = st.machines[i]
        -- 温度向设定值弛豫 + 抖动
        for k = 1, 6 do
            m.tp[k] = m.tp[k] + (m.sp[k] - m.tp[k]) * 0.06
                + 0.5 * math.sin(t / 7 + k + i)
        end
        -- 压力随工艺阶段起伏
        local load = 0.6 + 0.4 * math.sin(m.phase / 6 * 2 * math.pi)
        m.pr[1] = 125 * load + 2 * math.sin(t / 5 + i)
        m.pr[2] = 85 * load + 1.5 * math.sin(t / 6 + i)
        m.pr[3] = 12.5 + 0.8 * math.sin(t / 9 + i)
        m.pr[4] = 1286 + 20 * math.sin(t / 11 + i)
        m.clamp, m.pos = m.pr[4], 48.2 + 6 * math.sin(t / 4 + i)
        m.vel = 86 + 4 * math.sin(t / 8 + i)
        m.screw = 12.5 + 1.2 * math.sin(t / 7 + i)

        -- 工艺阶段推进，一圈完成出一模
        if st.running and not st.paused then
            m.phase_t = m.phase_t + 1
            if m.phase_t >= PHASE_DUR[m.phase + 1] then
                m.phase_t = 0
                m.phase = (m.phase + 1) % 6
                if m.phase == 0 then
                    m.shot = m.shot + 1
                    if math.random(100) > 2 then m.good = m.good + 1 end
                    m.cyc = 32.5 + 0.8 * math.sin(t / 50 + i)
                end
            end
        end
    end

    -- 趋势图推点（t1/t2/t5 温度、p1/p2 压力，取 1# 机）
    local m1 = st.machines[1]
    push_point(trend.t1, m1.tp[1])
    push_point(trend.t2, m1.tp[2])
    push_point(trend.t5, m1.tp[5])
    push_point(trend.p1, m1.pr[1])
    push_point(trend.p2, m1.pr[2])

    if REFRESH[page] then REFRESH[page]() end
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

-- 图片必须与 main.xml 同目录（plcui 只接受相对 XML 目录的 src）。
-- 真机：main.xml + 全部图片与脚本一起烧进 /luadb（源码组织在 code/res/，打包时平铺）；
-- PC 模拟器：直接把 code/ 交给模拟器，romfs 平铺后同样走 /luadb 分支。
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

    seed_trend()
    xml = load_xml()
    if not xml then
        return
    end
    page = "ov"
    refresh_ov()
    touch_bind()
    backlight_on()

    log.info("ui", "注塑产线 HMI 已就绪", machine_total() .. " 模")
    sys.timerLoopStart(tick, 1000)

    -- 传送带光点动画：8 帧透明 PNG 轮播（plcui 没有移动组件的 API，
    -- 产线的"流动"效果靠定时 set_src 切帧实现；停机/暂停时定格）
    local belt_frame = 0
    sys.timerLoopStart(function()
        if not st.running or st.paused then return end
        local o = find("anim_belt")
        if o then
            belt_frame = (belt_frame + 1) % 8
            o:set_src("anim_belt_" .. belt_frame)
        end
    end, 120)
end)

sys.run()
