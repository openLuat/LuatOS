--[[
@module  data_app
@summary 业务数据：EFEM-200 晶圆传输模块的节拍、机械手、真空与点位映像
@version 1.0.0
@date    2026.11.20
@usage
1、24.3 秒一个搬运周期，周期内分取片/送入/工艺/取回/送回五段；
2、真空度、N2 压力、机械手电流与腔体温度在设定值附近缓慢漂移；
3、每 200ms 提供一次采样，ui_app 按 1 Hz 追加到四张 chart。
对外接口 6 个：init / step / sample / get / set_bright / bright。
]]

local data_app = {}

local T_CYCLE = 24.3

local S = {
    tick = 0,
    clock_sec = 0 * 3600 + 23 * 60,
    cyc = 0,              -- 已完成周期数
    phase = 0,            -- 周期内进度 0..1
    vac = 0.31,           -- 腔体真空 Pa
    n2 = 0.40,            -- N2 压力 MPa
    cur = 2.4,            -- 机械手电流 A
    tmp = 23.6,           -- 腔体温度 ℃
    r_axis = 128.4,
    z_axis = -12.0,
    grip = -82.0,
    pm2 = true,           -- PM2 是否工艺中
    target = "PM2",
    bright = 82,
    events = {},
}

-- 千分位：1284300 -> 1,284,300
local function fmt_num(n)
    local t = tostring(math.floor(n or 0))
    local out = t:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

local function jitter(a)
    return (math.random() - 0.5) * 2 * a
end

local function now_clock()
    local s = S.clock_sec % 86400
    return string.format("%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60))
end

local function push_event(text)
    table.insert(S.events, 1, { t = now_clock(), x = text })
    while #S.events > 4 do table.remove(S.events) end
end

function data_app.init()
    S.tick, S.cyc, S.phase = 0, 0, 0
    S.events = {}
    push_event("示教点偏移 0.02 mm")
    push_event("LP2 开盒气压不足，已重试")
    push_event("PM3 抽气偏长 0.8 s")
    log.info("data", "EFEM 业务数据初始化完成")
end

--[[ 每秒推进：周期进度 + 各量缓慢变化 ]]
function data_app.step()
    S.tick = S.tick + 1
    S.clock_sec = S.clock_sec + 1
    S.phase = (S.phase + 1 / T_CYCLE) % 1
    if S.phase < 1 / T_CYCLE then
        S.cyc = S.cyc + 1
        if S.cyc % 12 == 0 then
            push_event(string.format("完成 %d 片搬运，节拍稳定", S.cyc))
        end
    end

    -- 周期分五段：0-22% 取片、22-43% 送入、43-52% 工艺、52-58% 取回、58-72% 送回、其余等待
    local p = S.phase
    if p < 0.22 then
        S.target, S.pm2 = "ALIGNER", false
    elseif p < 0.43 then
        S.target, S.pm2 = "PM2", false
    elseif p < 0.52 then
        S.target, S.pm2 = "PM2", true
    elseif p < 0.58 then
        S.target, S.pm2 = "ALIGNER", true
    elseif p < 0.72 then
        S.target, S.pm2 = "LP2", true
    else
        S.target, S.pm2 = "待机", false
    end

    local t = S.tick
    S.vac = 0.31 + 0.12 * math.sin(t / 9) + jitter(0.02) + (S.pm2 and 0.05 or 0)
    S.n2 = 0.40 + 0.03 * math.sin(t / 13) + jitter(0.005)
    S.cur = 2.4 + 0.9 * math.abs(math.sin(t / 7)) + jitter(0.15)
    S.tmp = 23.6 + 0.5 * math.sin(t / 21) + jitter(0.05)
    S.r_axis = 128.4 + 6 * math.sin(t / 11) + jitter(0.3)
    S.z_axis = -12.0 + 1.5 * math.sin(t / 5)
    S.grip = -82.0 + jitter(0.8)
end

--[[ 曲线采样：200ms 一次 ]]
function data_app.sample()
    return S.vac, S.n2, S.cur, S.tmp
end

--[[ 界面快照 ]]
function data_app.get()
    local v = {}
    v.clock = now_clock()
    v.tp_meta = string.format("FOUP A · 25 片 · RCP-28nm-A")

    v.kp_wph = "148"
    v.kp_ut = string.format("%.1f %%", 96.4 - 0.2 * math.abs(math.sin(S.tick / 30)))
    v.kp_ok = "搬运成功 99.98 %"

    v.rb_v0 = string.format("%.1f°", S.r_axis)
    v.rb_v1 = string.format("%.1f mm", S.z_axis)
    v.rb_v2 = string.format("%.0f kPa", S.grip)
    v.rb_v3 = string.format("%.1f A", S.cur)

    v.fl_to = (S.target == "待机") and "→ 等待取片" or ("→ 送入 " .. S.target)

    for i = 1, 3 do
        local e = S.events[i]
        v["ev_t" .. (i - 1)] = e and e.t or "--:--"
        v["ev_x" .. (i - 1)] = e and e.x or ""
    end

    v.ao_v0 = string.format("%d", 68)
    v.ao_v1 = string.format("%d", 54)
    v.ao_v2 = string.format("%d", 80)
    v.dg_l1 = string.format("周期 2.8 ms  负荷 22 %%")
    v.br_v = string.format("%d %%", S.bright)

    v.rd_v0 = "1,240 h"
    v.rd_v1 = fmt_num(86420 + S.cyc * 25)
    v.rd_v2 = "2"
    v.rd_v3 = "31 %"

    v.mt_v0 = fmt_num(1284300 + S.cyc * 8)
    v.mt_v1 = fmt_num(42180 + S.cyc * 2)
    v.mt_v2 = "1,240"
    v.mt_v3 = "860"

    local di = {
        { "I0.0", "急停", "ON" },
        { "I0.1", "LP1 有盒", "ON" },
        { "I0.2", "LP2 有盒", "ON" },
        { "I0.3", "门联锁", "ON" },
        { "I0.4", "真空到位", "ON" },
    }
    local do_ = {
        { "Q0.0", "LP1 开盒", "OFF" },
        { "Q0.1", "LP2 开盒", "ON" },
        { "Q0.2", "腔体抽气", (S.pm2) and "ON" or "OFF" },
        { "Q0.3", "N2 吹扫", "OFF" },
        { "Q0.4", "报警灯黄", "ON" },
    }
    local ai = {
        { "AI0", "腔体真空", string.format("%.2f Pa", S.vac) },
        { "AI1", "N2 压力", string.format("%.2f MPa", S.n2) },
        { "AI2", "R 轴电流", string.format("%.1f A", S.cur) },
        { "AI3", "腔体温度", string.format("%.1f ℃", S.tmp) },
        { "AI4", "洁净度", "ISO 3" },
    }
    return v, { di = di, do_ = do_, ai = ai }
end

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

function data_app.bright() return S.bright end

function data_app.clear_force()
    push_event("已取消全部强制点")
end

return data_app
