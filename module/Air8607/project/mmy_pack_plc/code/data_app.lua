--[[
@module  data_app
@summary 业务数据：储能模组 PACK 线的七工步、拧紧、气密、点位映像与报警
@version 1.0.0
@date    2026.11.17
@usage
本文件不碰界面，只回答「现在是什么状态」：
1、七工步按 42.2 秒一循环推进，工位拓扑与步序表共用同一套下标；
2、拧紧、气密只在各自工步内演化，其余工步保持上一次结果；
3、ui_app 取 get() 的快照，按 ui_vars 的绑定表刷到组件上。
对外接口 7 个：init / step / get / step_key / force / is_forced / clear_force。
]]

local data_app = {}

-- 七工步：与 XML 的 st_*（工位拓扑）和 sp_*（步序表）一一对应
local STEPS = {
    { key = "load",   name = "电芯上料", dur = 6.2,  desc = "52 颗 · 扫码校验" },
    { key = "stack",  name = "堆叠配组", dur = 12.4, desc = "极性复核 + 间隙" },
    { key = "weld",   name = "极耳焊接", dur = 8.8,  desc = "激光 1.8 kW" },
    { key = "insert", name = "模组入箱", dur = 5.6,  desc = "入箱 + 定位" },
    { key = "tight",  name = "螺栓拧紧", dur = 4.1,  desc = "8.5 N·m × 4 轴" },
    { key = "leak",   name = "气密测试", dur = 3.5,  desc = "25 kPa / 0.3" },
    { key = "mark",   name = "下线打码", dur = 1.6,  desc = "MES 过站" },
}

local AXIS = { "M1", "M2", "M3", "M4" }
local FORCE_TAG = { "M0.2", "Q0.2", "M0.5" }

local S = {
    tick = 0,
    step_i = 1,
    step_t = 0,
    step_seq = 0,
    cp = 0,        -- 曲线进度计数：5 拍 ≈ 1 秒（200ms 采样）
    cstep = 0,
    shot = 1284,
    good = 1275,
    bad = 9,
    stop_min = 23,
    clock_sec = 19 * 3600 + 41 * 60,
    tor = { 8.42, 8.38, 8.45, 8.40 },
    ang = { 42, 41, 43, 42 },
    leak_p = 25.0,
    leak_rate = 0.12,
    laser = 1.8,
    force = {},
    alarms = {},
}

-- 工步内的工艺曲线：入参是工步进度 0..1，1Hz 采样与 200ms 曲线插值共用
local function torque_at(p) return 0.6 + 7.9 * p ^ 1.35 end
local function angle_at(p) return 12 + 33 * p end
local function leak_at(p)
    -- 从 23.2 kPa 起压到 25.0，再缓慢衰减：曲线正好用满 23-26 的量程
    if p < 0.4 then return 23.2 + 1.8 * (p / 0.4) ^ 0.7 end
    return 25.0 - 0.9 * ((p - 0.4) / 0.6)
end

local function jitter(a)
    return (math.random() - 0.5) * 2 * a
end

local function now_clock()
    local s = S.clock_sec % 86400
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

local function push_event(text)
    table.insert(S.alarms, 1, { t = now_clock(), x = text })
    while #S.alarms > 6 do table.remove(S.alarms) end
end

function data_app.init()
    S.tick, S.step_i, S.step_t = 0, 1, 0
    S.cp, S.cstep = 0, 0
    S.alarms = {}
    push_event("拧紧轴 M3 扭矩偏差 +0.06，已自动复拧")
    push_event("气密 2 号腔泄漏率偏高，复测通过")
    push_event("焊接烟尘净化器压差高，待换滤芯")
    log.info("data", "业务数据初始化完成")
end

--[[ 每秒推进一次：步序 -> 工步量 -> 计数 ]]
function data_app.step()
    S.tick = S.tick + 1
    S.clock_sec = S.clock_sec + 1
    S.step_t = S.step_t + 1

    S.sub = 0
    local cur = STEPS[S.step_i]
    if S.step_t >= cur.dur then
        S.step_t = 0
        S.step_seq = S.step_seq + 1
        S.step_i = S.step_i + 1
        if S.step_i > #STEPS then
            S.step_i = 1
            S.shot = S.shot + 1
            S.good = S.good + 1
        end
        local nxt = STEPS[S.step_i]
        if nxt.key == "tight" then
            push_event(string.format("第 %d 模组进拧紧工位，4 轴启动", S.shot))
        elseif nxt.key == "leak" then
            push_event("拧紧合格，进入气密测试")
        elseif nxt.key == "mark" then
            push_event("气密合格，允许下线打码")
        end
        cur = nxt
    end

    -- 拧紧：工步内从 6.8 爬到 8.5；其余工步保持上一次结果
    if cur.key == "tight" then
        local p = math.min(1, S.step_t / cur.dur)
        for i = 1, #AXIS do
            S.tor[i] = torque_at(p) + jitter(0.04)
            S.ang[i] = angle_at(p) + jitter(0.6)
        end
    else
        for i = 1, #AXIS do
            S.tor[i] = S.tor[i] + jitter(0.004)
            S.ang[i] = math.min(45, S.ang[i] + jitter(0.05))
        end
    end

    -- 气密：加压到 25 kPa，稳压后缓慢衰减
    if cur.key == "leak" then
        local p = math.min(1, S.step_t / cur.dur)
        S.leak_p = leak_at(p)
        S.leak_rate = (p < 0.4) and 0.02 or (0.08 + 0.08 * ((p - 0.4) / 0.6))
    else
        S.leak_p = 25.0 + jitter(0.01)
        S.leak_rate = 0.12 + jitter(0.004)
    end
end

local function step_states()
    local out = {}
    for i = 1, #STEPS do
        if i < S.step_i then out[i] = "完成"
        elseif i == S.step_i then out[i] = "进行"
        else out[i] = "等待" end
    end
    return out
end

--[[ 点位映像：表格 1 行表头 + 5 行数据 ]]
local function io_cells()
    local cur = STEPS[S.step_i]
    local past_leak = (cur.key == "leak" or cur.key == "mark")
    local di = {
        { "I0.0", "启动按钮", "ON" },
        { "I0.1", "停止按钮", "OFF" },
        { "I0.2", "安全门闭合", "ON" },
        { "I0.3", "扭矩合格", (S.step_i > 5) and "ON" or "OFF" },
        { "I0.4", "气密合格", past_leak and "ON" or "OFF" },
    }
    local do_ = {
        { "Q0.0", "上料允许", (cur.key == "load") and "ON" or "OFF" },
        { "Q0.1", "拧紧启动", (cur.key == "tight") and "ON" or "OFF" },
        { "Q0.2", "气密放行", (cur.key == "leak") and "ON" or "OFF" },
        { "Q0.3", "输送电机", "ON" },
        { "Q0.4", "三色灯绿", "ON" },
    }
    local ai = {
        { "AI0", "拧紧扭矩", string.format("%.2f N·m", S.tor[1]) },
        { "AI1", "气密压力", string.format("%.1f kPa", S.leak_p) },
        { "AI2", "激光功率", string.format("%.1f kW", S.laser) },
        { "AI3", "环境温度", "23.4 ℃" },
        { "AI4", "母线电压", "540 V" },
    }
    return di, do_, ai
end

--[[ 曲线采样：200ms 一次，全程连续
     拧紧工步给实时扭矩、气密工步给实时压力，其余工步给保持值——
     曲线一直在滚，只是平段；进入对应工步时由界面先压平再从左侧画起 ]]
function data_app.sample()
    local cur = STEPS[S.step_i]
    S.hold_t = S.hold_t or 8.5
    S.hold_l = S.hold_l or 25.0
    -- 换工步时把计数清零；计数只由本函数自增，不被 1Hz 推进打断，
    -- 所以进度严格单调，不会出现「爬到一半又跳回去」的锯齿
    if S.cstep ~= S.step_i then
        S.cstep = S.step_i
        S.cp = 0
    end
    local p = math.min(1, (S.cp / 5) / cur.dur)
    S.cp = S.cp + 1
    -- 非检测工步沿用「最后一次采样值」而不是模型保持值，
    -- 否则工步切换那一刻值会跳变，曲线上出现一道台阶
    local t1 = S.hold_t
    local t3 = S.hold_t * 1.015
    local lp = S.hold_l
    if cur.key == "tight" then
        t1 = torque_at(p)
        t3 = t1 * 1.015
        S.hold_t = t1
    elseif cur.key == "leak" then
        lp = leak_at(p)
        S.hold_l = lp
    end
    return t1, t3, lp
end

--[[ 界面快照：v 是扁平绑定表，其余字段给 ui_app 做表格与图元用 ]]
function data_app.get()
    local cur = STEPS[S.step_i]
    local v = {}

    v.clock = now_clock()
    v.hd_cs = string.format("第 %d 模组 · %s", S.shot, cur.name)
    v.bn_t = string.format("自动运行 · 步序 0%d/07 %s", S.step_i, cur.name)
    v.bn_cyc = "节拍 42.6 s"
    v.step_note = string.format("0%d / 07 进行中", S.step_i)

    local oee = 86.2 + math.sin(S.tick / 37) * 0.4
    local yield_pct = S.good / (S.good + S.bad) * 100
    v.kp_v0 = "42.6"
    v.kp_v1 = tostring(S.shot)
    v.kp_v2 = string.format("%.1f", oee)
    v.kp_v3 = string.format("%.1f", yield_pct)

    for i = 1, #AXIS do
        v["ax_v" .. (i - 1)] = string.format("%.2f", S.tor[i])
        v["ax_a" .. (i - 1)] = string.format("%d°", math.floor(S.ang[i] + 0.5))
    end

    local st = step_states()
    for i = 1, #st do v["sp_s" .. (i - 1)] = st[i] end

    for i = 1, 3 do
        local a = S.alarms[i]
        v["al_t" .. (i - 1)] = a and a.t or "--:--"
        v["al_x" .. (i - 1)] = a and a.x or ""
    end

    v.rt_note = "4 轴全部合格"
    v.wd_v3 = string.format("%.1f", S.leak_p)
    v.wd_v4 = string.format("%.2f", S.leak_rate)
    v.br_v = string.format("亮度 %d %% · PWM3（GPIO13）", S.bright or 82)
    v.br_num = string.format("%d %%", S.bright or 82)
    v.sa_v0 = tostring(S.shot)
    v.sa_v1 = tostring(S.good)
    v.sa_v2 = tostring(S.bad)
    v.sa_v3 = tostring(S.stop_min)
    v.fc_note = string.format("%d 点强制", (S.force[1] and 1 or 0) + (S.force[2] and 1 or 0) + (S.force[3] and 1 or 0))

    local di, do_, ai = io_cells()
    return v, { di = di, do_ = do_, ai = ai, step_i = S.step_i, force = S.force }
end

function data_app.step_key() return STEPS[S.step_i].key end
-- 曲线重画时把进度计数一起归零，避免「曲线是新画的、进度却接着上一段」
function data_app.reset_curve() S.cp = 0 end
function data_app.step_seq() return S.step_seq end
-- 工步起点值：曲线置平用的基线
function data_app.base_of(key)
    if key == "tight" then return torque_at(0), torque_at(0) * 1.015 end
    if key == "leak" then return nil, nil, leak_at(0) end
    return nil
end
function data_app.step_count() return #STEPS end
function data_app.step_def(i) return STEPS[i] end

function data_app.set_bright(v)
    S.bright = math.floor((tonumber(v) or 82) + 0.5)
    if S.bright < 10 then S.bright = 10 end
    if S.bright > 100 then S.bright = 100 end
    pcall(function()
        pwm.setup(3, 1000, S.bright)
        pwm.start(3)
    end)
    return S.bright
end

function data_app.bright() return S.bright or 82 end

--[[ 强制表：点按切换，强制值优先于实时映像 ]]
function data_app.force(idx)
    S.force[idx] = not S.force[idx]
    push_event(string.format("%s %s", FORCE_TAG[idx] or "?", S.force[idx] and "已强制 ON" or "已取消强制"))
    return S.force[idx]
end

function data_app.clear_force()
    S.force = {}
    push_event("已取消全部强制点")
end

function data_app.is_forced(idx) return S.force[idx] == true end

return data_app
