--[[
@module  data_app
@summary 智能注塑车间 1# 产线 · 业务数据与工艺量模拟
@version 1.0.0
@date    2026.11.16
@author  江访
@usage
本文件是界面的数据源，不碰任何 PLCUI 组件，只对上层暴露一张变量表与一组命令：
1、data_app.init      初始化工艺曲线缓冲、随机源与开机时间；
2、data_app.step      每秒推进一步（工艺量、产量、OEE、节拍），由 boot_app 的定时器调用；
3、data_app.get       返回当前变量表，键名与 ui_vars.lua 的 BIND 表一一对应；
4、data_app.cmd_start / cmd_stop / cmd_reset / cmd_estop   主控四键；
5、data_app.set_setpoint / set_bright / toggle_sw / set_param / commit_params   参数侧写入；
6、data_app.select_device / ack_one / ack_all / clear_acked  设备与报警操作。
本文件的对外接口有 22 个。
]]

local data_app = {}

-- 工艺量程：与 main.xml 里 chart 的 0~100 归一化视野对应
local TMIN, TMAX = 180, 260
local PMIN, PMAX = 60, 120

-- 曲线缓冲长度取两张图的最大点数（总览 60 点、趋势页 80 点）
local BUF = 80

-- 主控设定值范围
local SP_MIN, SP_MAX = 180, 260

-- 面板背光：PWM 通道与 boot_app 上电时序保持一致，亮度百分比直接当占空比
local BL_PWM_CH, BL_PWM_FREQ = 3, 1000
local IS_PC = rtos.bsp() == "PC"

local function apply_backlight(pct)
    if IS_PC or not pwm then return end
    pwm.setup(BL_PWM_CH, BL_PWM_FREQ, pct)
    pwm.start(BL_PWM_CH)
end

local st = {
    running = true,
    estop = false,
    sp = 220,
    out = 1286,          -- 当班产量
    total = 86542,       -- 累计产量
    oee = 89.4,
    cycle = 28.4,
    bright = 70,
    sel = -1,            -- 选中的设备，-1 表示全线
    temp = {},           -- 模温采样缓冲
    press = {},          -- 射胶压力采样缓冲
    sw = { true, true, false },   -- 蜂鸣器 / 班次切换 / 趋势存储
    boot = 0,            -- 开机时刻（os.time 秒）
    tick = 0,            -- 秒计数（os.time 不可用时兜底走时）
}

-- 控制器参数：id 与 main.xml 里 textarea 的 id 一致
local params = { p1 = 245, p2 = 195, p3 = 12.0, p4 = 45, p5 = 250, p6 = 115 }
local p_fmt = { p1 = "%.0f", p2 = "%.0f", p3 = "%.1f", p4 = "%.0f", p5 = "%.0f", p6 = "%.0f" }
local p_limit = {
    p1 = { 200, 260 }, p2 = { 150, 220 }, p3 = { 0.1, 99.9 },
    p4 = { 1, 999 }, p5 = { 10, 2000 }, p6 = { 20, 160 },
}
local p_name = {
    p1 = "模温上限", p2 = "模温下限", p3 = "PID 比例带",
    p4 = "PID 积分时间", p5 = "通讯轮询周期", p6 = "射胶压力上限",
}

-- 三台注塑机：基准状态与额定负载
local devices = {
    { name = "注塑机 A", code = "IMM-A01", base = "运行", load = 82, fault = false },
    { name = "注塑机 B", code = "IMM-B02", base = "待机", load = 15, fault = false },
    { name = "注塑机 C", code = "IMM-C03", base = "故障", load = 0,  fault = true },
}

-- 报警队列：最新的一条在最前
local alarms = {
    { lv = "严重", t = "14:12:30", d = "液压系统压力低于安全阈值 62 MPa", ack = false },
    { lv = "警告", t = "13:58:02", d = "2# 模温偏差 +4.5 ℃，接近上限", ack = false },
    { lv = "警告", t = "13:40:11", d = "润滑油脂位偏低，建议补充", ack = true },
    { lv = "提示", t = "12:05:44", d = "安全门联锁信号抖动，已记录", ack = true },
    { lv = "提示", t = "11:22:18", d = "合模压力波动超出 ±3%，已自恢复", ack = true },
    { lv = "提示", t = "10:48:03", d = "班次交接完成，参数已归档", ack = true },
}

local alarm_seq = 0
local last_msg = "系统就绪"

-- ==================== 内部工具 ====================

--[[ 随机浮点：[-1, 1) ]]
local function noise()
    return math.random() * 2 - 1
end

--[[ 限幅 ]]
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

--[[ 把工艺值归一化到 0~100，供 chart 使用（chart 只吃 -1000~1000） ]]
local function norm_t(v)
    return (clamp(v, TMIN, TMAX) - TMIN) / (TMAX - TMIN) * 100
end

local function norm_p(v)
    return (clamp(v, PMIN, PMAX) - PMIN) / (PMAX - PMIN) * 100
end

--[[ 取当前时间：优先 os.time；取不到就用开机秒数兜底 ]]
local function now_sec()
    local ok, t = pcall(os.time)
    if ok and type(t) == "number" and t > 0 then
        return t
    end
    return st.boot + st.tick
end

--[[ 格式化为 2026-11-16 15:04:05；os.date 不可用时自算 ]]
local function clock_text()
    local t = now_sec()
    local ok, s = pcall(os.date, "%Y-%m-%d %H:%M:%S", t)
    if ok and type(s) == "string" and #s == 19 then
        return s
    end
    local d = os.date and nil
    return string.format("2026-11-16 %02d:%02d:%02d",
        math.floor((t % 86400) / 3600), math.floor((t % 3600) / 60), t % 60)
end

--[[ 班次：08:00~20:00 白班 ]]
local function shift_text()
    local t = now_sec() % 86400
    local h = math.floor(t / 3600)
    if h >= 8 and h < 20 then
        return "白班 A 组"
    end
    return "夜班 B 组"
end

--[[ 设备当前状态：急停 / 停机 / 正常三档 ]]
local function dev_state(d)
    if st.estop then
        return "急停", 0, "lamp_alarm", "dot_fault"
    end
    if not st.running then
        if d.fault then
            return "故障", 0, "lamp_alarm", "dot_fault"
        end
        return "待机", math.floor(d.load * 0.35), "lamp_idle", "dot_idle"
    end
    if d.fault then
        return "故障", 0, "lamp_alarm", "dot_fault"
    end
    if d.base == "待机" then
        return "待机", d.load, "lamp_idle", "dot_idle"
    end
    return "运行", d.load, "lamp_run", "dot_run"
end

--[[ 负载百分比换算成填充条宽度（条全长 296px） ]]
local function bar_w(pct)
    local w = math.floor(296 * pct / 100 + 0.5)
    if w < 1 then return 1 end
    return w
end

--[[ 模温角度：-135° ~ +135°，返回值单位是「度」 ]]
local function temp_angle(v)
    return -135 + norm_t(v) / 100 * 270
end

local function press_angle(v)
    return -135 + norm_p(v) / 100 * 270
end

--[[ 从缓冲里取最后 n 个点并归一化 ]]
local function tail_series(buf, n, fn)
    local out = {}
    local from = #buf - n + 1
    if from < 1 then from = 1 end
    for i = from, #buf do
        out[#out + 1] = math.floor(fn(buf[i]) * 100 + 0.5) / 100
    end
    return out
end

--[[ 设定值目标线：整条常量，点数与主图一致 ]]
local function flat_series(n, v)
    local out = {}
    for i = 1, n do
        out[i] = v
    end
    return out
end

-- ==================== 对外：生命周期 ====================

--[[ 初始化：随机源、曲线种子、开机时刻 ]]
function data_app.init()
    math.randomseed(now_sec() % 100000)
    st.boot = now_sec()
    st.temp = {}
    st.press = {}
    for i = 1, BUF do
        st.temp[i] = 220 + math.sin(i / 9) * 4.2 + math.sin(i / 3.1) * 0.9 + noise() * 0.7
        st.press[i] = 88 + math.sin(i / 11) * 5.5 + math.cos(i / 4.3) * 1.1 + noise() * 0.6
    end
    log.info("data", "工艺量缓冲就绪", BUF, "点")
end

--[[ 每秒推进：工艺量跟随设定值，运行态才累计产量 ]]
function data_app.step()
    st.tick = st.tick + 1
    local active = st.running and not st.estop

    local t = st.temp[#st.temp]
    local p = st.press[#st.press]
    local jitter_t, jitter_p
    if active then
        jitter_t = math.sin(st.tick / 6) * 1.6 + noise() * 0.6
        jitter_p = math.cos(st.tick / 8) * 2.0 + noise() * 0.7
    else
        jitter_t = noise() * 0.3
        jitter_p = noise() * 0.4
    end

    local nt = t + (st.sp - t) * 0.09 + jitter_t
    local np = p + (88 - p) * 0.12 + jitter_p
    st.temp[#st.temp + 1] = clamp(nt, TMIN + 2, TMAX - 2)
    st.press[#st.press + 1] = clamp(np, PMIN + 2, PMAX - 2)
    table.remove(st.temp, 1)
    table.remove(st.press, 1)

    if active then
        if math.random() < 0.42 then
            st.out = st.out + 1
            st.total = st.total + 1
        end
        st.oee = clamp(st.oee + noise() * 0.5, 84, 94)
        st.cycle = clamp(st.cycle + noise() * 0.3, 26.5, 30.5)
    end
end

-- ==================== 对外：变量表 ====================

--[[ 返回界面要用的全部变量；键名即 ui_vars.lua 里的 var 字段 ]]
function data_app.get()
    local t = st.temp[#st.temp]
    local p = st.press[#st.press]
    local active = st.running and not st.estop

    local v = {
        clock = clock_text(),
        shift = shift_text(),
        running = st.running,
        estop = st.estop,
        sp = st.sp,
        bright = st.bright,

        status_text = st.estop and "紧急停机" or (st.running and "运行中" or "已停止"),
        lamp = st.estop and "lamp_alarm" or (st.running and "lamp_run" or "lamp_idle"),
        comm_led = st.estop and "dot_idle" or "dot_run",
        comm_txt = st.estop and "PROFINET · 链路告警 · 请排查后复位"
            or "PROFINET · 通讯正常 · 延迟 4 ms",
        pipe_txt = st.estop and "阀门 关断 · 介质截止"
            or (st.running and "阀门 开 · 介质流动 · DN40 · 16 MPa"
                or "阀门 开 · 保压待机 · DN40 · 16 MPa"),

        -- KPI
        kpi1 = string.format("%d", st.out),
        foot1 = string.format("当班目标 1600 件 · 达成 %.1f%%", st.out / 1600 * 100),
        kpi2 = active and string.format("%.1f", st.oee) or "--",
        kpi3 = string.format("%.1f", t),
        foot3 = string.format("设定值 %d ℃ · 上限 245 ℃", st.sp),
        kpi4 = active and string.format("%.1f", st.cycle) or "--",
        foot4 = active and string.format("标准节拍 28.0 s · 偏差 %+.1f%%",
            (st.cycle - 28) / 28 * 100) or "标准节拍 28.0 s · 偏差 --",

        -- 仪表与详情
        v_t = string.format("%.1f", t),
        v_p = string.format("%.1f", p),
        nd_t = temp_angle(t),
        nd_p = press_angle(p),
        dt1 = string.format("%.1f ℃", t),
        dt2 = string.format("%.1f MPa", p),
        dt3 = string.format("%d ℃", st.sp),
        dt4 = active and string.format("%.1f %%", st.oee) or "-- %",
        dt5 = (st.running and not st.estop) and "2 / 3 台" or "0 / 3 台",
        dt6 = string.format("%d 件", st.out),
        dev_title = st.sel < 0 and "■ 全线综合参数 / LINE"
            or ("■ 设备详情 · " .. devices[st.sel + 1].code),

        -- 趋势页
        st_t = string.format("%.1f", t),
        st_p = string.format("%.1f", p),
        st_sp = string.format("%d", st.sp),
        st_d = string.format("%+.1f", t - st.sp),

        -- 底栏
        total_out = string.format("%d", st.total),
        sp_val = string.format("%d", st.sp),
        knob_angle = -135 + (st.sp - SP_MIN) / (SP_MAX - SP_MIN) * 270,

        -- 报警
        al_cnt = tostring(data_app.unack_count()) .. " 未确认",
        tab_num = tostring(data_app.unack_count()),
        al_stat = string.format("未确认报警 %d 条 · 累计记录 %d 条",
            data_app.unack_count(), #alarms),

        -- 参数页
        st_br = string.format("%d%%", st.bright),
        st_msg = last_msg,

        -- 曲线（归一化到 0~100）
        ch_ov_t = tail_series(st.temp, 60, norm_t),
        ch_ov_p = tail_series(st.press, 60, norm_p),
        ch_ov_s = flat_series(60, math.floor(norm_t(st.sp) * 100 + 0.5) / 100),
        ch_tr_t = tail_series(st.temp, 80, norm_t),
        ch_tr_p = tail_series(st.press, 80, norm_p),
        ch_tr_s = flat_series(80, math.floor(norm_t(st.sp) * 100 + 0.5) / 100),
    }

    -- 设备卡：状态文本 / 指示灯 / 负载 / 填充条
    for i = 1, #devices do
        local d = devices[i]
        local text, load, lsrc, dsrc = dev_state(d)
        v["st" .. (i - 1)] = text
        v["ld" .. (i - 1)] = string.format("%d %%", load)
        v["led" .. (i - 1)] = dsrc
        v["bar" .. (i - 1)] = bar_w(load)
        v["barc" .. (i - 1)] = (text == "故障" or text == "急停") and "barfill_f"
            or (text == "待机" and "barfill_i" or "barfill_g")
        v["sel" .. (i - 1)] = (st.sel == i - 1)
    end

    -- 报警前三行
    for i = 1, 3 do
        local a = alarms[i]
        if a then
            v["alv" .. (i - 1)] = a.lv
            v["alt" .. (i - 1)] = a.t
            v["ald" .. (i - 1)] = a.d
            v["ad" .. (i - 1)] = a.ack and "dot_off" or (a.lv == "严重" and "dot_fault" or "dot_idle")
            v["ak" .. (i - 1)] = a.ack and "ack_d" or "ack_n"
            v["akd" .. (i - 1)] = a.ack
        end
    end

    -- 参数框
    for id, val in pairs(params) do
        v[id] = string.format(p_fmt[id], val)
    end
    for i = 1, 3 do
        v["sw" .. i] = st.sw[i]
    end

    return v
end

-- ==================== 对外：主控命令 ====================

function data_app.cmd_start()
    if st.estop then
        last_msg = "急停锁定中，请先执行复位"
        return false
    end
    st.running = true
    last_msg = "全线启动 · 曲线恢复活跃"
    return true
end

function data_app.cmd_stop()
    st.running = false
    last_msg = "全线停止 · 产量冻结"
    return true
end

function data_app.cmd_reset()
    st.estop = false
    st.running = false
    last_msg = "系统已复位，请重新启动"
    return true
end

function data_app.cmd_estop()
    st.estop = true
    st.running = false
    alarm_seq = alarm_seq + 1
    table.insert(alarms, 1, {
        lv = "严重", t = "现在",
        d = "急停按钮触发 · 全线安全停机，动力已切断",
        ack = false,
    })
    while #alarms > 12 do
        table.remove(alarms)
    end
    last_msg = "▲ 紧急停机已触发，新增 1 条严重报警"
    return true
end

-- ==================== 对外：设定值与参数 ====================

function data_app.set_setpoint(v)
    st.sp = clamp(math.floor(v + 0.5), SP_MIN, SP_MAX)
    last_msg = string.format("模温设定值已设为 %d ℃", st.sp)
    return st.sp
end

function data_app.set_bright(v)
    st.bright = clamp(math.floor(v + 0.5), 0, 100)
    apply_backlight(st.bright)
    return st.bright
end

--[[ 当前背光亮度，boot_app 点背光时取它，避免与滑块初值不一致 ]]
function data_app.bright_level()
    return st.bright
end

function data_app.toggle_sw(i)
    if i < 1 or i > #st.sw then return end
    st.sw[i] = not st.sw[i]
    return st.sw[i]
end

--[[ 参数写入：越界不落盘，返回 false 让界面回滚显示 ]]
function data_app.set_param(id, value)
    local lim = p_limit[id]
    if not lim then return false, "未知参数" end
    if type(value) ~= "number" then return false, "输入不是有效数字" end
    if value < lim[1] or value > lim[2] then
        return false, string.format("%s 超出范围 %.1f ~ %.1f", p_name[id], lim[1], lim[2])
    end
    params[id] = value
    last_msg = string.format("%s 已写入 %.1f", p_name[id], value)
    return true
end

function data_app.commit_params()
    last_msg = "参数已写入控制器 · CRC 校验通过 · 校验码 0x1A4F"
    return true
end

function data_app.param_text(id)
    if params[id] == nil then return "" end
    return string.format(p_fmt[id], params[id])
end

-- ==================== 对外：设备与报警 ====================

function data_app.select_device(i)
    if i < 0 or i > #devices - 1 then
        st.sel = -1
    elseif st.sel == i then
        st.sel = -1
    else
        st.sel = i
    end
    return st.sel
end

function data_app.device_param(i)
    local d = devices[i + 1]
    if not d then return nil end
    return d
end

function data_app.unack_count()
    local n = 0
    for i = 1, #alarms do
        if not alarms[i].ack then n = n + 1 end
    end
    return n
end

function data_app.ack_one(i)
    local a = alarms[i + 1]
    if not a or a.ack then return false end
    a.ack = true
    last_msg = string.format("报警已确认 · %s", a.d)
    return true
end

function data_app.ack_all()
    for i = 1, #alarms do
        alarms[i].ack = true
    end
    last_msg = "已确认全部报警"
    return true
end

function data_app.clear_acked()
    local kept = {}
    for i = 1, #alarms do
        if not alarms[i].ack then
            kept[#kept + 1] = alarms[i]
        end
    end
    alarms = kept
    last_msg = "已清除已确认记录"
    return true
end

--[[ 报警表数据：第 1 行是表头，行数与 main.xml 的 rows 对齐 ]]
function data_app.alarm_rows()
    local rows = { { "级别", "发生时间", "设备 / 回路", "报警描述", "状态", "处理" } }
    for i = 1, #alarms do
        local a = alarms[i]
        rows[#rows + 1] = {
            a.lv, a.t, "1# 产线", a.d,
            a.ack and "已确认" or "未确认", a.ack and "已归档" or "待处理",
        }
        if #rows >= 7 then break end
    end
    while #rows < 7 do
        rows[#rows + 1] = { "", "", "", "", "", "" }
    end
    return rows
end

function data_app.last_msg()
    return last_msg
end

return data_app
