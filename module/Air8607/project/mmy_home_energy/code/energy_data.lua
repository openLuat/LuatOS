--[[
@module  energy_data
@summary 家庭能源数据引擎（光伏 / 负载 / 储能 / 电网 仿真 + 24h 与 7/30 天历史）
@version 1.0
@date    2026.10.26

=== 这一层负责什么 ===
界面只读 M.state / M.today / M.circuits 这些字段，**不自己算能量**。
把真实采集接进来时（MQTT / Modbus 电表 / 逆变器私有协议），
只要按同样的字段往里写值，UI 一行都不用改：

  M.state.load  当前家庭负载 kW（正数，恒为正）
  M.state.pv    当前光伏发电 kW
  M.state.bat   储能功率 kW：正=充电，负=放电
  M.state.soc   储能电量 0..100
  M.state.grid  电网功率 kW：正=买电，负=卖电
  M.state.hour  当前时刻 0..24（小数）
  M.today.*     今日累计电量 / 电费 / 减排

=== 仿真模型 ===
负载 = 8 个分路当前功率之和，每个分路是"额定功率 x 时段曲线 x 抖动"。
时段曲线用高斯包络（起床 / 午饭 / 傍晚高峰），比正弦更像真实家庭负荷。
光伏 = 装机容量 x 日照包络 x 天气系数，包络中心 12:24、半宽 3.3 小时。
储能按当前电价策略动作：有光伏余量就充、峰段就放，余量/缺额都受功率上限约束。
电网 = 负载 + 充电 - 放电 - 光伏，正数买电、负数卖电 —— 这样四个数字永远自洽。
]]

local M = {}

-- ==================== 配置 ====================
M.cfg = {
    pv_kwp     = 8.60,      -- 光伏装机 8.6 kWp
    bat_kwh    = 10.0,      -- 储能容量 10 kWh
    bat_ch_max = 3.20,      -- 最大充电功率 kW
    bat_dis_max = 3.00,     -- 最大放电功率 kW
    price = {
        valley = 0.32,      -- 谷电（23:00 - 07:00）
        flat   = 0.56,      -- 平电
        peak   = 0.62,      -- 峰电（08:00-11:00 / 18:00-21:00）
    },
    feed_in  = 0.38,        -- 余电上网电价
    co2      = 0.581,       -- 电网电力的碳排放因子 kg/kWh
    weather  = 0.88,        -- 天气系数：1.0 晴 / 0.6 多云 / 0.3 阴雨
}

-- 储能策略
-- name 是屏幕上的四个字，say 是语音里补给人听的一句解释：
-- "峰谷套利"这种词，写出来成立，念出来没人听得懂，必须跟一句大白话。
M.BAT_MODE = {
    { id = 1, name = "自发自用", say = "光伏发的电先给家里用，用不完再存进电池" },
    { id = 2, name = "峰谷套利", say = "电价便宜的时候充电，电价贵的时候放电" },
    { id = 3, name = "备电优先", say = "电池尽量留着，停电的时候还能顶上" },
}

-- ==================== 分路 ====================
--[[
pat 决定"这个电器什么时候开"，值域 0..1：
  ac      空调（午后到夜间，随室外温度抬升）
  water   热水器（早晚各一次，功率大、时间短）
  kitchen 厨房（三餐）
  wash    洗衣机（白天）
  light   照明（日落后）
  fridge  冰箱（几乎恒定，压缩机间歇）
  tv      影音（晚间）
  misc    其他（常开小负载）
]]
M.circuits = {
    { id = "ac",      name = "空调",   kw = 2.60, pat = "ac",      on = true,  color = 0x4C8DFF },
    { id = "water",   name = "热水器", kw = 1.80, pat = "water",   on = true,  color = 0xFF8A5C },
    { id = "kitchen", name = "厨房",   kw = 1.50, pat = "kitchen", on = true,  color = 0xFFC247 },
    { id = "wash",    name = "洗衣机", kw = 0.52, pat = "wash",    on = true,  color = 0x9C7BFF },
    { id = "light",   name = "照明",   kw = 0.36, pat = "light",   on = true,  color = 0x2BE0C8 },
    { id = "fridge",  name = "冰箱",   kw = 0.16, pat = "fridge",  on = true,  color = 0x3FE08F },
    { id = "tv",      name = "影音",   kw = 0.28, pat = "tv",      on = true,  color = 0x5FA8FF },
    { id = "misc",    name = "其他",   kw = 0.30, pat = "misc",    on = true,  color = 0x7A8FA6 },
}
M.NCIRC = #M.circuits

-- ==================== 状态 ====================
M.state = {
    hour = 9.2, load = 0, pv = 0, bat = 0, soc = 62.0, grid = 0,
    bat_mode = 1, sim_t = 0,
}

M.today = {
    load = 0, pv = 0, buy = 0, sell = 0, cost = 0, income = 0, co2 = 0,
}

-- 24 小时曲线（96 点，15 分钟一格）
M.NPT = 96
M.day = { load = {}, pv = {} }

-- 7 天 / 30 天历史（每日 kWh）
M.week = { load = {}, pv = {}, n = 7 }
M.month = { load = {}, pv = {}, n = 30 }

-- ==================== 工具 ====================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
M.clamp = clamp

-- 高斯包络：中心 c、半宽 s
local function gauss(x, c, s)
    local d = (x - c) / s
    return math.exp(-d * d)
end

-- ==================== 时段曲线 ====================
--[[光伏日照包络 0..1
不是正弦：早上爬升慢、正午最平、傍晚掉得快，高斯更贴近实测曲线。]]
local function pv_shape(h)
    if h < 5.6 or h > 18.9 then return 0 end
    return gauss(h, 12.4, 3.30)
end
M.pv_shape = pv_shape

local function pat_value(pat, h)
    if pat == "ac" then
        return clamp(0.18 + 0.82 * gauss(h, 15.2, 3.6), 0, 1)
    elseif pat == "water" then
        return clamp(gauss(h, 7.0, 1.05) + 0.88 * gauss(h, 20.8, 1.45), 0, 1)
    elseif pat == "kitchen" then
        return clamp(0.95 * gauss(h, 7.2, 0.85) + 1.0 * gauss(h, 12.2, 0.95)
            + 0.92 * gauss(h, 18.4, 1.15), 0, 1)
    elseif pat == "wash" then
        return clamp(0.55 * gauss(h, 10.0, 1.8) + 0.45 * gauss(h, 16.0, 1.6), 0.06, 1)
    elseif pat == "light" then
        if h < 5.8 or h > 17.6 then
            return clamp(0.45 + 0.55 * gauss(h, 20.0, 3.0), 0, 1)
        end
        return 0.10
    elseif pat == "fridge" then
        -- 压缩机间歇：主值 0.75 + 半小时周期的启停起伏
        return 0.62 + 0.30 * math.abs(math.sin(h * 3.4))
    elseif pat == "tv" then
        return clamp(gauss(h, 20.2, 2.1), 0, 1)
    end
    return 0.72      -- misc：常开小负载
end

-- 单个分路在 h 时刻的功率（不含抖动）
local function circ_kw(c, h)
    if not c.on then return 0 end
    return c.kw * pat_value(c.pat, h)
end

-- 全部负载（不含抖动）
function M.load_at(h)
    local sum = 0
    for i = 1, M.NCIRC do
        sum = sum + circ_kw(M.circuits[i], h)
    end
    return sum
end

-- 某一时刻的光伏出力
function M.pv_at(h)
    return M.cfg.pv_kwp * pv_shape(h) * M.cfg.weather
end

-- ==================== 电价 ====================
function M.price_at(h)
    if h < 7 or h >= 23 then return M.cfg.price.valley, "谷" end
    if (h >= 8 and h < 11) or (h >= 18 and h < 21) then return M.cfg.price.peak, "峰" end
    return M.cfg.price.flat, "平"
end

-- ==================== 历史曲线 ====================
--[[重建今日 24h 曲线（分路开关变化 / 天气变化后调用）
96 个点 x 2 条曲线 = 192 次求值，几十微秒的事，开关一次电器重算一次完全值得。]]
function M.rebuild_day()
    local step = 24 / M.NPT
    for i = 1, M.NPT do
        local h = (i - 1) * step
        M.day.load[i] = M.load_at(h)
        M.day.pv[i] = M.pv_at(h)
    end
end

--[[重建 7 天 / 30 天历史
按"每天的总用电"生成：周末略高、天气逐日波动。

用固定种子的线性同余发生器（不用 math.random）：
每次开机、每次联动重算出来的历史曲线都一模一样，
这样"把空调关掉之后柱状图掉了多少"才是可复现、可拍照对比的。]]
function M.rebuild_history()
    local seed = 20261026
    local function rnd()
        seed = (seed * 16807) % 2147483647
        return seed / 2147483647
    end
    -- 7 天
    for i = 1, M.week.n do
        local weekend = (i >= 6) and 1.16 or 1.0
        local l = 0
        for k = 0, 23, 0.5 do l = l + M.load_at(k) * 0.5 end
        l = l * weekend * (0.86 + 0.30 * rnd())
        M.week.load[i] = l
        M.week.pv[i] = M.cfg.pv_kwp * 6.9 * M.cfg.weather * (0.55 + 0.70 * rnd())
    end
    -- 30 天
    for i = 1, M.month.n do
        local weekend = ((i % 7) == 6 or (i % 7) == 0) and 1.15 or 1.0
        local l = 0
        for k = 0, 23, 1 do l = l + M.load_at(k) end
        l = l * weekend * (0.84 + 0.34 * rnd())
        M.month.load[i] = l
        M.month.pv[i] = M.cfg.pv_kwp * 6.9 * M.cfg.weather * (0.50 + 0.75 * rnd())
    end
end

-- ==================== 储能策略 ====================
--[[储能动作：返回功率（正=充电，负=放电）与策略文案
入参 excess 是"光伏 - 负载"（正=有余量，负=缺额），peak 表示当前是否峰段。
三种策略的区别只在"什么时候愿意放电"：
  自发自用 —— 只要有光伏余量就充、缺电就放，尽量不让电过网
  峰谷套利 —— 谷段充满、峰段才放，平段只补极端缺口
  备电优先 —— 只在谷段充到 90% 就停，平时不轻易放（留给停电）
]]
local function bat_action(excess, soc, peak, hour, mode)
    local reserve = (mode == 3) and 88 or 22      -- 备电优先保留到 88% 才肯放
    if mode == 2 then reserve = 30 end
    if soc <= reserve then
        -- 需要补电：有光伏余量优先用余量，没有就走谷电
        if excess > 0.10 and soc < 92 then
            return math.min(excess, M.cfg.bat_ch_max), "光伏充电"
        end
        if mode == 2 and (hour < 7 or hour >= 23) and soc < 92 then
            return M.cfg.bat_ch_max * 0.8, "谷电充电"
        end
        if soc < 16 then return math.min(M.cfg.bat_ch_max * 0.6, 1.6), "强制补电" end
        return 0, "待机"
    end
    if excess > 0.10 and soc < 97 then
        return math.min(excess, M.cfg.bat_ch_max), "光伏充电"
    end
    if excess < -0.10 and soc > reserve + 4 then
        if mode == 1 then
            return -math.min(-excess, M.cfg.bat_dis_max), "放电供家"
        elseif mode == 2 then
            if peak then return -math.min(-excess, M.cfg.bat_dis_max), "峰时放电" end
            return 0, "待机"
        else
            if peak then return -math.min(-excess, M.cfg.bat_dis_max), "峰时放电" end
            return 0, "待机"
        end
    end
    return 0, (soc >= 97) and "充满待机" or "待机"
end

-- ==================== 初始化 ====================
function M.init()
    -- 有 RTC 就跟着真实时间走，没有就从上午 9 点起（演示态）
    local h = nil
    local ok, d = pcall(os.date, "*t")
    if ok and type(d) == "table" and d.hour then
        h = d.hour + (d.min or 0) / 60
    end
    M.state.hour = h or 9.2
    M.state.soc = 62.0
    M.state.bat_mode = 1
    M.rebuild_day()
    M.rebuild_history()
    M.settle(0, true)
    log.info("energy", string.format("数据引擎启动 hour=%.2f 分路=%d", M.state.hour, M.NCIRC))
end

-- ==================== 单步推进 ====================
--[[结算当前时刻的功率与累计电量
@param number dth 推进的"仿真小时"数
@param boolean force 强制重算（开机第一帧用）
]]
function M.settle(dth, force)
    local s, cfg = M.state, M.cfg
    local h = s.hour

    -- 分路抖动：让读数像真的在跳，但不是随机乱跳（用固定相位 + 慢正弦）
    local load = 0
    for i = 1, M.NCIRC do
        local c = M.circuits[i]
        local j = 1 + 0.055 * math.sin(s.sim_t * 0.9 + i * 1.7)
        c.now = circ_kw(c, h) * j
        load = load + c.now
    end
    s.load = load
    s.pv = M.pv_at(h) * (1 + 0.03 * math.sin(s.sim_t * 0.21))

    local price, seg = M.price_at(h)
    s.price, s.seg = price, seg

    local excess = s.pv - s.load
    local bat, why = bat_action(excess, s.soc, seg == "峰", h, s.bat_mode)
    s.bat = bat
    s.bat_why = why
    s.grid = s.load + s.bat - s.pv

    -- 电量累计：功率 kW x 小时
    if dth and dth > 0 then
        local e_load = s.load * dth
        local e_pv = s.pv * dth
        local e_buy = math.max(s.grid, 0) * dth
        local e_sell = math.max(-s.grid, 0) * dth
        M.today.load = M.today.load + e_load
        M.today.pv = M.today.pv + e_pv
        M.today.buy = M.today.buy + e_buy
        M.today.sell = M.today.sell + e_sell
        M.today.cost = M.today.cost + e_buy * price
        M.today.income = M.today.income + e_sell * cfg.feed_in
        M.today.co2 = M.today.co2 + (e_pv + e_sell) * cfg.co2
        -- 储能 SOC
        s.soc = clamp(s.soc + bat * dth / cfg.bat_kwh * 100, 0, 100)
    end
end

--[[主推进：dt 是真实秒
time_speed 是仿真倍率（默认 60：1 秒 = 1 分钟）]]
function M.tick(dt, speed)
    local s = M.state
    speed = speed or 60
    s.sim_t = s.sim_t + dt
    local dth = dt * speed / 3600        -- 仿真小时
    s.hour = s.hour + dth
    if s.hour >= 24 then
        -- 跨天：先把今天累计的用电/发电钉进历史（明天它就是"昨天"），再清空今日
        s.hour = s.hour - 24
        local y_load, y_pv = M.today.load, M.today.pv
        for i = 2, M.week.n do
            M.week.load[i - 1], M.week.pv[i - 1] = M.week.load[i], M.week.pv[i]
        end
        M.week.load[M.week.n] = y_load
        M.week.pv[M.week.n] = y_pv
        for i = 2, M.month.n do
            M.month.load[i - 1], M.month.pv[i - 1] = M.month.load[i], M.month.pv[i]
        end
        M.month.load[M.month.n] = y_load
        M.month.pv[M.month.n] = y_pv

        M.today.load, M.today.pv = 0, 0
        M.today.buy, M.today.sell = 0, 0
        M.today.cost, M.today.income, M.today.co2 = 0, 0, 0
        log.info("energy", string.format("跨天，昨日用电 %.2fkWh 已归档", y_load))
    end
    M.settle(dth, false)
end

-- ==================== 外部操作 ====================
-- 切换分路开关（模拟智能插座 / 智能断路器）
function M.toggle_circuit(i)
    local c = M.circuits[i]
    if not c then return nil end
    c.on = not c.on
    M.rebuild_day()
    M.rebuild_history()
    M.settle(0, false)
    log.info("energy", "分路 " .. c.name .. (c.on and " 已开启" or " 已关闭"))
    return c.on
end

function M.total_on()
    local n = 0
    for i = 1, M.NCIRC do
        if M.circuits[i].on then n = n + 1 end
    end
    return n
end

function M.set_bat_mode(mode)
    M.state.bat_mode = mode
    M.settle(0, false)
    log.info("energy", "储能策略 " .. (M.BAT_MODE[mode] and M.BAT_MODE[mode].name or "?"))
end

function M.cycle_bat_mode()
    local m = M.state.bat_mode % #M.BAT_MODE + 1
    M.set_bat_mode(m)
    return m
end

-- ==================== 派生指标 ====================
-- 自给率：自家发电 + 储能顶上来的比例（1 - 买电/用电）
function M.self_rate()
    if M.today.load < 0.05 then return 0 end
    return clamp(1 - M.today.buy / M.today.load, 0, 1)
end

-- 净支出（正=花钱）
function M.net_cost()
    return M.today.cost - M.today.income
end

-- 当前时刻在今日曲线里的下标
function M.now_index()
    local i = math.floor(M.state.hour / 24 * M.NPT) + 1
    return clamp(i, 1, M.NPT)
end

-- 时钟字符串（演示态下按仿真时间走，接 RTC 后自动跟真实时间）
function M.clock_str()
    local h = M.state.hour
    local hh = math.floor(h) % 24
    local mm = math.floor((h - math.floor(h)) * 60)
    return string.format("%02d:%02d", hh, mm)
end

return M
