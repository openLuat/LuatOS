--[[
@module  sim
@summary ReefOS 数据与业务模型：水质演化、光谱、设备、喂食/补水/换水、事件与报警
@version 1.0
@date    2026.10.27
   说明：本项目无外接传感器，所有水质数据由本地物理模型 + 随机扰动模拟，
        但各项之间存在真实的因果关系（加热棒影响水温、蒸发抬升盐度、
        喂食抬升营养盐、蛋白分离器与换水降低营养盐……），便于演示与联调。
]]
local conf = require "conf"

local M = {}

M.paused = false
M.tick_count = 0
M.sim_min = 0

local N = conf.sim.history or 48

local store = {}       -- key -> {def, value, hist, manual, th}
local order = {}       -- 全部参数 key 顺序
local devs = {}        -- key -> device
local dev_order = {}
local spec = { blue = 55, white = 70, uv = 40 }
local alarms = {}
local feed_count = 0
local last_feed_min = 0
local last_water_min = 0
local fired = {}
local env = { room = 26.4, hum = 58, kwh = 0.00 }
local power_w = 0

-- ===================== 工具 =====================
local function clamp(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end

local function rnd(a)
    return (math.random() * 2 - 1) * a
end

function M.clock()
    return os.date("%H:%M")
end

function M.date_text()
    local t = os.date("*t")
    local wd = { "日", "一", "二", "三", "四", "五", "六" }
    return string.format("%d月%d日 周%s", t.month, t.day, wd[t.wday])
end

-- 0..1，0 表示 00:00
function M.day_phase()
    local t = os.date("*t")
    return (t.hour * 60 + t.min) / 1440
end

-- 光照强度曲线（日出 6:30 / 日落 19:00）
function M.light_curve(phase)
    phase = phase or M.day_phase()
    local sunrise, sunset = 6.5 / 24, 19 / 24
    if phase < sunrise or phase > sunset then return 0 end
    local t = (phase - sunrise) / (sunset - sunrise)
    return math.sin(t * math.pi)
end

function M.is_night()
    local h = tonumber(os.date("%H")) or 12
    return h >= 19 or h < 7
end

-- ===================== 初始化 =====================
function M.init()
    store, order, devs, dev_order, alarms, fired = {}, {}, {}, {}, {}, {}
    M.tick_count, M.sim_min, feed_count, last_feed_min, last_water_min = 0, 0, 0, 0, 0
    M.paused = false
    env = { room = 26.4, hum = 58, kwh = 0.00 }
    spec = { blue = conf.spectrum.default.blue, white = conf.spectrum.default.white, uv = conf.spectrum.default.uv }

    for _, d in ipairs(conf.metrics) do
        local v = d.base
        local st = {
            def = d,
            value = v,
            manual = nil,
            hist = {},
            th = { lo = d.lo, hi = d.hi, dlo = d.dlo, dhi = d.dhi },
        }
        for i = 1, N do
            st.hist[i] = v + rnd(d.jitter) * 2
        end
        st.hist[N] = v
        store[d.key] = st
        order[#order + 1] = d.key
    end

    for _, d in ipairs(conf.devices) do
        local item = { key = d.key, name = d.name, icon = d.icon, note = d.note, on = d.on }
        devs[d.key] = item
        dev_order[#dev_order + 1] = d.key
    end

    M.log_event("系统启动，水质模型已就绪", "ok")
    M.recalc_power()
end

-- ===================== 参数读写 =====================
function M.def(key) return store[key] and store[key].def end
function M.state(key) return store[key] end
function M.keys() return order end
function M.value(key) local st = store[key]; return st and st.value end
function M.hist(key) local st = store[key]; return st and st.hist or {} end

function M.fmt(key, v)
    local st = store[key]
    if not st then return "--" end
    return string.format("%." .. st.def.dec .. "f", v or st.value)
end

function M.unit(key)
    local st = store[key]
    return st and st.def.unit or ""
end

function M.level(key)
    local st = store[key]
    if not st then return "ok" end
    local v, th = st.value, st.th
    if (th.dlo and v < th.dlo) or (th.dhi and v > th.dhi) then return "danger" end
    if (th.lo and v < th.lo) or (th.hi and v > th.hi) then return "warn" end
    return "ok"
end

-- 参数在 0..1 中的位置（用于进度条）
function M.ratio(key)
    local st = store[key]
    if not st then return 0 end
    local d = st.def
    return clamp((st.value - d.min) / (d.max - d.min), 0, 1)
end

function M.ratio_of(key, v)
    local st = store[key]
    if not st then return 0 end
    local d = st.def
    return clamp((v - d.min) / (d.max - d.min), 0, 1)
end

-- 滑块换算（滑块只支持整数）
function M.to_slider(key, v)
    local st = store[key]
    if not st then return 0 end
    local s = st.def.scale or 1
    return math.floor((v or st.value) * s + 0.5)
end

function M.from_slider(key, sv)
    local st = store[key]
    if not st then return 0 end
    local s = st.def.scale or 1
    return sv / s
end

function M.is_manual(key)
    local st = store[key]
    return st ~= nil and st.manual ~= nil
end

function M.set_value(key, v)
    local st = store[key]
    if not st then return end
    st.value = clamp(v, st.def.min, st.def.max)
    st.manual = st.value
    M.push(key, st.value)
end

function M.clear_manual(key)
    local st = store[key]
    if st then st.manual = nil end
end

function M.threshold(key)
    local st = store[key]
    return st and st.th or {}
end

function M.set_threshold(key, which, v)
    local st = store[key]
    if not st then return end
    st.th[which] = v
end

function M.push(key, v)
    local st = store[key]
    if not st then return end
    local h = st.hist
    h[#h + 1] = v
    if #h > N then table.remove(h, 1) end
end

-- ===================== 设备 =====================
function M.devices() return dev_order, devs end
function M.device(key) return devs[key] end
function M.device_on(key)
    local d = devs[key]
    return d and d.on or false
end

function M.on_count()
    local n = 0
    for _, k in ipairs(dev_order) do
        if devs[k].on then n = n + 1 end
    end
    return n
end

function M.toggle_device(key)
    local d = devs[key]
    if not d then return end
    d.on = not d.on
    M.log_event(d.name .. (d.on and " 已开启" or " 已关闭"), d.on and "ok" or "warn")
    M.recalc_power()
    return d.on
end

function M.recalc_power()
    local w = 18
    if devs.pump and devs.pump.on then w = w + 45 end
    if devs.wave and devs.wave.on then w = w + 28 end
    if devs.skimmer and devs.skimmer.on then w = w + 22 end
    if devs.heater and devs.heater.on then w = w + 120 end
    if devs.chiller and devs.chiller.on then w = w + 210 end
    if devs.uv and devs.uv.on then w = w + 30 end
    w = w + math.floor((spec.blue + spec.white + spec.uv) * 1.05)
    power_w = w
end

function M.power() return power_w end

-- ===================== 光谱 =====================
function M.spectrum() return spec end

function M.set_spectrum(key, v)
    spec[key] = clamp(math.floor(v), 0, 100)
    M.recalc_power()
end

function M.spectrum_preset_name()
    for _, p in ipairs(conf.spectrum.presets) do
        if p.blue == spec.blue and p.white == spec.white and p.uv == spec.uv then
            return p.name
        end
    end
    return "自定义"
end

function M.apply_preset(idx)
    local p = conf.spectrum.presets[idx]
    if not p then return end
    spec.blue, spec.white, spec.uv = p.blue, p.white, p.uv
    M.recalc_power()
    M.log_event("光照切换到「" .. p.name .. "」", "ok")
    return p
end

function M.presets() return conf.spectrum.presets end

-- ===================== 维护操作 =====================
function M.feed()
    feed_count = feed_count + 1
    last_feed_min = M.sim_min
    local st = store.no3
    if st and not st.manual then st.value = clamp(st.value + 0.85, st.def.min, st.def.max) end
    local sp = store.po4
    if sp and not sp.manual then sp.value = clamp(sp.value + 0.011, sp.def.min, sp.def.max) end
    M.log_event("手动投喂（今日第 " .. feed_count .. " 次）", "ok")
    return "已投喂，3 分钟后自动恢复造浪"
end

function M.topup()
    local st = store.sal
    if st then
        st.value = 1.0248
        st.manual = nil
        M.push("sal", st.value)
    end
    M.log_event("RO 水补水 2L，比重回到 1.025", "ok")
    return "补水完成，盐度回到 1.025"
end

function M.water_change()
    last_water_min = M.sim_min
    local function cut(key, f)
        local st = store[key]
        if st and not st.manual then
            st.value = st.def.min + (st.value - st.def.min) * f
            M.push(key, st.value)
        end
    end
    cut("no3", 0.72)
    cut("po4", 0.70)
    local kh = store.kh
    if kh and not kh.manual then kh.value = clamp(kh.value + 0.35, kh.def.min, kh.def.max) end
    M.log_event("换水 10%（90L），营养盐下降", "ok")
    return "换水完成，硝酸盐与磷酸盐已下降"
end

function M.feed_remain_min()
    local next_feed = last_feed_min + (conf.sim.feed_interval_min or 120)
    local r = next_feed - M.sim_min
    return r > 0 and r or 0
end

function M.feed_count() return feed_count end

function M.last_feed_ago_min()
    return M.sim_min - last_feed_min
end

function M.water_remain_min()
    local nextw = last_water_min + (conf.sim.water_interval_min or 4320)
    local r = nextw - M.sim_min
    return r > 0 and r or 0
end

function M.ago_text(min)
    min = math.floor(min)
    if min < 1 then return "刚刚" end
    if min < 60 then return min .. " 分钟前" end
    local h = math.floor(min / 60)
    local m = min % 60
    if h < 24 then return h .. " 小时" .. (m > 0 and (m .. " 分") or "") .. "前" end
    return math.floor(h / 24) .. " 天前"
end

function M.remain_text(min)
    min = math.floor(min)
    if min < 60 then return min .. " 分钟" end
    local h = math.floor(min / 60)
    local m = min % 60
    return h .. " 小时" .. (m > 0 and (m .. " 分") or "")
end

-- ===================== 事件与报警 =====================
function M.log_event(text, level)
    alarms[#alarms + 1] = {
        text = text,
        level = level or "ok",
        time = os.date("%H:%M"),
        min = M.sim_min,
    }
    while #alarms > 30 do table.remove(alarms, 1) end
end

-- 最新的在前
function M.alarms(n)
    local list = {}
    local total = #alarms
    local cnt = n or total
    for i = 0, cnt - 1 do
        local idx = total - i
        if idx >= 1 then list[#list + 1] = alarms[idx] end
    end
    return list
end

function M.alarm_count() return #alarms end

function M.worst_level()
    local worst = "ok"
    for _, k in ipairs(order) do
        local lv = M.level(k)
        if lv == "danger" then return "danger" end
        if lv == "warn" then worst = "warn" end
    end
    return worst
end

function M.abnormal_count()
    local n = 0
    for _, k in ipairs(order) do
        if M.level(k) ~= "ok" then n = n + 1 end
    end
    return n
end

-- ===================== 环境 =====================
function M.env() return env end

function M.auto_feed_on() return true end

-- ===================== 演化 =====================
local prev_level = {}

function M.tick()
    if M.paused then return end
    M.tick_count = M.tick_count + 1
    M.sim_min = M.sim_min + (conf.sim.min_per_tick or 3)

    local heater = M.device_on("heater")
    local chiller = M.device_on("chiller")
    local skimmer = M.device_on("skimmer")
    local pump = M.device_on("pump")

    -- 光照
    local light = M.light_curve()
    local night = M.is_night()

    -- 水温：向设备设定点 + 灯热缓慢靠拢
    local temp = store.temp
    if not temp.manual then
        local target = 25.5
        if heater and chiller then target = 25.3
        elseif heater then target = 26.0
        elseif chiller then target = 24.9 end
        target = target + light * 0.25 - (night and 0.12 or 0)
        temp.value = temp.value + (target - temp.value) * 0.16 + rnd(temp.def.jitter)
        temp.value = clamp(temp.value, temp.def.min, temp.def.max)
    end

    -- 盐度：蒸发使比重上升，泵开着蒸发更快
    local sal = store.sal
    if not sal.manual then
        local evap = pump and 0.000075 or 0.000045
        sal.value = clamp(sal.value + evap + rnd(sal.def.jitter), sal.def.min, sal.def.max)
    end

    -- pH：白天光合作用拉高
    local ph = store.ph
    if not ph.manual then
        local target = 8.05 + light * 0.16 - (store.no3.value > 12 and 0.08 or 0)
        ph.value = ph.value + (target - ph.value) * 0.20 + rnd(ph.def.jitter)
        ph.value = clamp(ph.value, ph.def.min, ph.def.max)
    end

    -- 碱度 / 钙 / 镁：珊瑚消耗
    local kh = store.kh
    if not kh.manual then
        kh.value = clamp(kh.value - 0.014 - rnd(0.002), kh.def.min, kh.def.max)
    end
    local ca = store.ca
    if not ca.manual then
        ca.value = clamp(ca.value - 0.28 - rnd(0.05), ca.def.min, ca.def.max)
    end
    local mg = store.mg
    if not mg.manual then
        mg.value = clamp(mg.value - 0.09 - rnd(0.02), mg.def.min, mg.def.max)
    end

    -- 营养盐：喂食累积，分离器与换水削减
    local no3 = store.no3
    if not no3.manual then
        local d = 0.05 - (skimmer and 0.035 or 0)
        no3.value = clamp(no3.value + d + rnd(0.02), no3.def.min, no3.def.max)
    end
    local po4 = store.po4
    if not po4.manual then
        local d = 0.0009 - (skimmer and 0.0006 or 0)
        po4.value = clamp(po4.value + d + rnd(0.0004), po4.def.min, po4.def.max)
    end

    -- 自动喂食
    if M.feed_remain_min() <= 0 then
        M.feed()
    end

    -- 定时事件（演示用）
    for i, e in ipairs(conf.events) do
        if not fired[i] and M.tick_count >= e.after then
            fired[i] = true
            local st = store[e.key]
            if st then
                st.value = clamp(st.value + e.delta, st.def.min, st.def.max)
                st.manual = nil
                M.push(e.key, st.value)
            end
            M.log_event(e.text, "warn")
        end
    end

    -- 落历史 + 越限记录
    for _, k in ipairs(order) do
        local st = store[k]
        M.push(k, st.value)
        local lv = M.level(k)
        if prev_level[k] and prev_level[k] ~= lv and lv ~= "ok" then
            local d = st.def
            M.log_event(string.format("%s %s%s，%s正常区间", d.name, M.fmt(k),
                (d.unit ~= "" and d.unit or ""), lv == "danger" and "超出" or "偏离"), lv)
        end
        prev_level[k] = lv
    end

    -- 环境与能耗
    env.room = env.room + (25.8 - env.room) * 0.05 + rnd(0.05)
    env.hum = clamp(env.hum + rnd(0.6), 42, 72)
    env.kwh = env.kwh + power_w / 1000 * (conf.sim.interval_ms / 3600000) * 40
    env.power = power_w
end

return M
