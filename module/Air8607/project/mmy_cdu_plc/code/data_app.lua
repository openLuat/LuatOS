--[[
@module  data_app
@summary 业务数据：CDU-1200 液冷机组的一二次侧回路、泵组、补水与能效
@version 1.0.0
@date    2026.11.18
@usage
本文件不碰界面，只回答「现在是什么状态」：
1、一次侧（设施冷冻水）与二次侧（机柜冷却液）的温度、压差、流量在设定值附近缓慢漂移；
2、换热量由二次侧流量与供回温差反算，保证与两处读数自洽；
3、每 200ms 提供一次曲线采样，供 ui_app 追加到三张 chart。
对外接口 6 个：init / step / sample / get / set_bright / bright。
]]

local data_app = {}

local S = {
    tick = 0,
    clock_sec = 20 * 3600 + 2 * 60,
    p1 = 78.0,          -- P1 频率 %
    p2 = 0.0,           -- P2 频率 %（热备）
    vl = 62.0,          -- 三通阀位 %
    ts = 32.4,          -- 二次侧供液 ℃
    tr = 40.6,          -- 二次侧回液 ℃
    dp = 165.0,         -- 二次侧压差 kPa
    flow = 105.0,       -- 二次侧流量 m3/h
    tas = 12.0,         -- 一次侧供水 ℃
    tar = 18.5,         -- 一次侧回水 ℃
    tap = 180.0,        -- 一次侧压差 kPa
    taflow = 132.0,     -- 一次侧流量 m3/h
    level = 68.0,       -- 膨胀罐液位 %
    makeup = 0.8,       -- 补水量 m3/h
    run_h = 412,
    start_n = 38,
    rot_n = 12,
    bright = 82,
    alarms = {},
}

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
    S.tick = 0
    S.alarms = {}
    push_event("补水阀动作 12 s，液位恢复 68 %")
    push_event("二次侧压差偏低 3 kPa，已自动提频")
    push_event("P2 热备泵轮换试运转完成")
    log.info("data", "CDU 业务数据初始化完成")
end

--[[ 每秒推进：负荷缓慢变化 -> 温度、压差、泵频跟随 ]]
function data_app.step()
    S.tick = S.tick + 1
    S.clock_sec = S.clock_sec + 1
    S.run_h = S.run_h + 1 / 3600

    local t = S.tick
    -- 机房负荷：慢波 + 小幅随机
    local load = 0.5 + 0.5 * math.sin(t / 16)
    S.p1 = 62 + 26 * load + jitter(0.6)
    S.vl = 48 + 26 * load + jitter(0.8)

    -- 二次侧：供液温度随负荷上升，回液再高 8 K 左右
    S.ts = 31.6 + 1.2 * load + jitter(0.06)
    S.tr = S.ts + 7.9 + 0.5 * load + jitter(0.08)
    S.dp = 160 + 9 * load + jitter(0.7)
    S.flow = 98 + 12 * load + jitter(0.4)

    -- 一次侧：与二次侧耦合，温差约 6.4 K
    S.tas = 11.8 + jitter(0.05)
    S.tar = S.tas + 6.4 + 0.2 * load + jitter(0.06)
    S.tap = 178 + jitter(0.6)
    S.taflow = S.flow * 1.26 + jitter(0.3)

    S.level = 68 + 0.6 * math.sin(t / 48) + jitter(0.05)
    S.makeup = 0.8 + 0.05 * math.sin(t / 31)
end

--[[ 曲线采样：200ms 一次，返回 6 个瞬时值 ]]
function data_app.sample()
    return S.ts, S.tr, S.dp, S.p1, S.vl, S.p2
end

--[[ 由二次侧流量与供回温差反算换热量，保证与读数自洽：
     Q(kW) = 1.163 × 流量(m3/h) × ΔT(K) ]]
local function heat_kw()
    return 1.163 * S.flow * (S.tr - S.ts)
end

--[[ 界面快照 ]]
function data_app.get()
    local v = {}
    local q = heat_kw()
    local dt = S.tr - S.ts

    v.clock = now_clock()
    v.hd_cs = string.format("负载 %d %% · 自动运行", math.floor(S.p1 / 82 * 100 + 0.5))
    v.bn_q = string.format("换热 %d kW / 额定 1200", math.floor(q + 0.5))
    local cop = 6.0 - 0.004 * S.p1
    v.bn_cop = string.format("COP %.1f", cop)
    v.bn_dt = string.format("ΔT %.1f K", dt)

    v.kp_v0 = string.format("%d", math.floor(q + 0.5))
    v.kp_v1 = string.format("%.1f", S.ts)
    v.kp_v2 = string.format("%.1f", dt)
    v.kp_v3 = string.format("%d", math.floor(S.p1 + 0.5))

    v.pm_fv0 = string.format("%d %%", math.floor(S.p1 + 0.5))
    v.pm_fv1 = "0 %"
    v.pm_cv0 = string.format("%.1f A", S.p1 * 0.592)
    v.pm_cv1 = "0.0 A"

    v.t_s1 = string.format("%.1f ℃", S.tas)
    v.t_r1 = string.format("%.1f ℃", S.tar)
    v.t_s2 = string.format("%.1f ℃", S.ts)
    v.t_r2 = string.format("%.1f ℃", S.tr)
    v.p1_t = string.format("%d %%", math.floor(S.p1 + 0.5))

    v.a_v0 = string.format("%.1f", S.tas)
    v.a_v1 = string.format("%.1f", S.tar)
    v.a_v2 = string.format("%d", math.floor(S.tap + 0.5))
    v.a_v3 = string.format("%d", math.floor(S.taflow + 0.5))
    v.bb_v0 = string.format("%.1f", S.ts)
    v.bb_v1 = string.format("%.1f", S.tr)
    v.bb_v2 = string.format("%d", math.floor(S.dp + 0.5))
    v.bb_v3 = string.format("%d", math.floor(S.flow + 0.5))

    v.ef_v0 = string.format("%d", math.floor(q + 0.5))
    v.ef_v1 = string.format("%.1f", cop)
    v.ef_v2 = string.format("%.1f", S.ts - S.tas - 20 + 1.2)

    v.mu_v0 = string.format("%d", math.floor(S.level + 0.5))
    v.mu_v1 = string.format("%.1f", S.makeup)
    v.mu_v2 = "0.8"

    v.ao_v0 = string.format("%d", math.floor(S.p1 + 0.5))
    v.ao_v1 = string.format("%d", math.floor(S.vl + 0.5))
    v.ao_v2 = "0"

    v.fc_note = "0 点强制"
    v.br_v = string.format("亮度 %d %% · PWM3（GPIO13）", S.bright)
    v.br_num = string.format("%d %%", S.bright)

    v.en_v0 = string.format("%.1f", q * 24 * 3.6 / 1000)
    v.en_v1 = string.format("%.1f", cop)
    v.en_v2 = string.format("%.2f", 1.02 + 0.06 * (1 - S.p1 / 100))
    v.en_v3 = string.format("%d", math.floor(S.run_h))

    v.rd_v0 = string.format("%d h", math.floor(S.run_h))
    v.rd_v1 = tostring(S.start_n)
    v.rd_v2 = tostring(S.rot_n)
    v.rd_v3 = "36 %"

    for i = 1, 3 do
        local a = S.alarms[i]
        v["al_t" .. (i - 1)] = a and a.t or "--:--"
        v["al_x" .. (i - 1)] = a and a.x or ""
    end

    -- 点位映像
    local di = {
        { "I0.0", "急停回路", "ON" },
        { "I0.1", "双泵运行", "ON" },
        { "I0.2", "膨胀罐低液位", (S.level < 40) and "ON" or "OFF" },
        { "I0.3", "漏液报警", "OFF" },
        { "I0.4", "电源双路", "ON" },
    }
    local do_ = {
        { "Q0.0", "P1 运行", "ON" },
        { "Q0.1", "P2 运行", "OFF" },
        { "Q0.2", "补水电磁阀", (S.makeup > 0.82) and "ON" or "OFF" },
        { "Q0.3", "三通调节阀", "ON" },
        { "Q0.4", "风机", "ON" },
    }
    local ai = {
        { "AI0", "供液温度", string.format("%.1f ℃", S.ts) },
        { "AI1", "回液温度", string.format("%.1f ℃", S.tr) },
        { "AI2", "供回压差", string.format("%d kPa", math.floor(S.dp + 0.5)) },
        { "AI3", "流量", string.format("%d m3/h", math.floor(S.flow + 0.5)) },
        { "AI4", "膨胀罐液位", string.format("%d %%", math.floor(S.level + 0.5)) },
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

--[[ 强制表：单点，切一次记一条事件 ]]
function data_app.force(idx)
    S.forced = not S.forced
    push_event(S.forced and "M0.1 P2 允许 已强制 ON" or "M0.1 P2 允许 已取消强制")
    return S.forced
end

function data_app.clear_force()
    S.forced = false
    push_event("已取消全部强制点")
end

function data_app.is_forced() return S.forced == true end

return data_app
