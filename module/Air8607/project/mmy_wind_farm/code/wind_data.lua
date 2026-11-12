--[[
@module  wind_data
@summary 北岭风电场数据引擎（12 台机组 + 尾流模型 + 全场功率 + 风向玫瑰 + 事件流）
@version 1.0
@date    2026.11.09

=== 这一层负责什么 ===
界面只读 M.turbines / M.state / M.today / M.events / M.rose 这些字段，**不自己算功率**。
接真实采集时（风机 SCADA / Modbus / IEC104 / MQTT 网关）按同样字段往里写值，
UI 一行都不用改：

  M.turbines[i].power   单机有功 MW
  M.turbines[i].wind    该机轮毂处有效风速 m/s（已含尾流折减）
  M.turbines[i].status  0 发电 / 1 待风 / 2 故障 / 3 检修停机
  M.state.wind          全场平均风速 m/s
  M.state.dir           风向（气象方位：0 = 北，顺时针）
  M.state.power         全场有功 MW
  M.state.curtail_limit 调度限电上限 MW（0 = 不限电）
  M.today.mwh           今日发电量 MWh

=== 物理模型 ===
1、风速：基值 + 两个不同周期的正弦（天气尺度与阵风尺度），倍率 60 倍时
   一分钟走一小时，屏幕上的风速是一条会呼吸的曲线，不是随机噪声。
2、尾流：把 12 台机按机位坐标投影到风的流向上，上游有多少台在挡，就折减多少，
   单机最多折 30%。风向一转，整片阵列的出力分布会跟着变 —— 这是风电场大屏上
   最有信息量的一个细节：下风向那两列永远比上风向暗一点。
3、功率曲线：切入 3 m/s，额定 11.5 m/s，切出 25 m/s，中间按三次方上升。
4、限电：调度给一个上限，超出的部分按比例压到每台机上，同时累计"限电损失"。
5、事件流是**状态边沿**（故障、复机、限电、解限、阵风），不是定时刷屏。
]]

local M = {}

-- ==================== 配置 ====================
M.cfg = {
    cap_each  = 6.25,   -- 单机容量 MW（12 台 = 75 MW 装机）
    cut_in    = 3.0,    -- 切入风速 m/s
    rated     = 11.5,   -- 额定风速 m/s
    cut_out   = 25.0,   -- 切出风速 m/s
    price     = 0.42,   -- 上网电价 元/kWh
    co2       = 0.581,  -- 排放因子 kg/kWh（折算减排用）
    wake      = 0.075,  -- 每台上游机组的尾流折减
    wake_max  = 0.30,   -- 单机尾流折减上限
    curt_ratio = 0.62,  -- 调度限电时压到装机的百分比
}

M.N = 12
M.NCAP = M.cfg.cap_each * M.N

-- 机位：4 列 x 3 行，坐标单位 km（x 向东，y 向北），用于尾流投影
M.turbines = {}

-- ==================== 状态 ====================
M.state = {
    sim_t = 0,
    hour = 9.0,
    wind = 8.6,
    dir = 315,
    gust = 0,
    power = 0,
    avail = 100,
    curt = false,          -- 当前是否处于限电
    curtail_limit = 0,     -- 限电上限 MW
    online = 12,
}

M.today = {
    mwh = 0,       -- 今日发电量
    peak = 0,      -- 今日功率峰值 MW
    loss = 0,      -- 限电损失 MWh
    faults = 0,    -- 今日故障次数
}

-- 96 点（15 分钟一格）历史：实测 + 预测
M.NPT = 96
M.hist = { meas = {}, fcst = {} }

-- 风向玫瑰：16 个方位（N, NNE, ...），freq 是累积小时数，spd 是该方位的平均风速
M.ROSE_N = 16
M.rose = { freq = {}, spd = {} }

-- 事件流（1 = 最新）
M.events = {}
M.MAX_EVENT = 20

-- ==================== 工具 ====================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
M.clamp = clamp

-- 固定种子线性同余发生器：每次开机生成的扰动完全一样，现象可复现
local seed = 20261109
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
end

local function gauss(x, c0, s)
    local d = (x - c0) / s
    return math.exp(-d * d)
end

local function hhmm(h)
    local hh = math.floor(h) % 24
    local mm = math.floor((h - math.floor(h)) * 60)
    return string.format("%02d:%02d", hh, mm)
end
M.hhmm = hhmm

-- 方位角 -> 英文罗盘（屏上只用 ASCII，不用箭头）
local COMPASS = { "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                  "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW" }
function M.compass(dir)
    local i = math.floor(((dir % 360) + 11.25) / 22.5) % 16 + 1
    return COMPASS[i], i
end

-- ==================== 事件流 ====================
function M.log_event(level, text)
    local e = { t = hhmm(M.state.hour), level = level, text = text, ts = M.state.sim_t }
    table.insert(M.events, 1, e)
    for i = #M.events, M.MAX_EVENT + 1, -1 do M.events[i] = nil end
    return e
end

function M.ack_event(i)
    local e = M.events[i]
    if not e or e.level == 0 then return false end
    e.level = 0
    return true
end

function M.ack_all()
    local n = 0
    for i = 1, #M.events do
        if M.events[i].level > 0 then
            M.events[i].level = 0
            n = n + 1
        end
    end
    return n
end

function M.active_alarms()
    local n = 0
    for i = 1, #M.events do
        if M.events[i].level >= 2 then n = n + 1 end
    end
    return n
end

-- ==================== 功率曲线 ====================
-- 单机有功：切入以下 0，额定以上满发，之间三次方
local function pcurve(v, cap)
    local cfg = M.cfg
    if v < cfg.cut_in or v >= cfg.cut_out then return 0 end
    if v >= cfg.rated then return cap end
    local t = (v - cfg.cut_in) / (cfg.rated - cfg.cut_in)
    return cap * t * t * t
end
M.pcurve = pcurve

-- ==================== 初始化 ====================
local function build_turbines()
    M.turbines = {}
    for i = 1, M.N do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        M.turbines[i] = {
            name = string.format("WT-%02d", i),
            short = string.format("%02d", i),
            col = col, row = row,
            px = col * 0.9,                  -- km，向东
            py = row * 1.35,                 -- km，向北
            cap = M.cfg.cap_each,
            phase = (i * 0.7) % 6.283,       -- 转子初始相位，12 台不同步更好看
            power = 0, wind = 0, weff = 0, rpm = 0,
            pitch = 0, temp = 45,
            status = 0, fault_t = 0, stop = false, curt = false,
        }
    end
end

--[[24 小时风速模型：夜强昼弱（陆上风电的典型日变化），叠加两个尺度的小波动]]
local function wind_at(h)
    return 8.6
        + 2.5 * math.sin((h - 3) / 24 * 6.2832)   -- 天气尺度：凌晨起风、午后回落
        + 1.0 * math.sin(h * 0.82 + 1.1)          -- 小时尺度
        + 0.5 * math.sin(h * 2.31)                -- 湍流尺度
end
M.wind_at = wind_at

--[[重建今日 96 点曲线
实测按"该时刻风速能发多少"算，预测按同一模型加一点相位偏差 —— 于是两条线
始终有点差，看起来像真的预测系统，而不是把实测复制一份。]]
function M.rebuild_hist()
    for k = 1, M.NPT do
        local h = (k - 1) * 24 / M.NPT
        local v = wind_at(h)
        local p = 0
        for i = 1, M.N do p = p + pcurve(v, M.cfg.cap_each) end
        -- 预测通常偏乐观一点点，且相位提前 20 分钟
        local vf = wind_at(h + 0.33) * 1.03
        local pf = 0
        for i = 1, M.N do pf = pf + pcurve(vf, M.cfg.cap_each) end
        M.hist.meas[k] = p
        M.hist.fcst[k] = pf
    end
end

-- 风向玫瑰的初始分布：这个场站冬季主导西北风，先给一条"已经观测过很久"的玫瑰
local function seed_rose()
    for i = 1, M.ROSE_N do
        local ang = (i - 1) * 22.5
        local w = 0.45
            + 3.2 * gauss(ang, 315, 34)       -- 主导：西北
            + 1.1 * gauss(ang, 45, 30)        -- 次主导：东北
        M.rose.freq[i] = w
        M.rose.spd[i] = 6.5 + 1.8 * math.sin(i * 0.9)
    end
end

function M.init()
    local ok, d = pcall(os.date, "*t")
    local h = 9.0
    if ok and type(d) == "table" and d.hour then h = d.hour + (d.min or 0) / 60 end
    M.state.hour = h
    M.state.wind = wind_at(h)
    M.state.dir = 315 + 18 * math.sin(h * 0.4)
    M.state.sim_t = 0
    M.state.gust = 0
    M.state.power = 0
    M.state.curt = false
    M.state.curtail_limit = 0
    M.state.online = M.N
    M.today.mwh, M.today.peak, M.today.loss, M.today.faults = 0, 0, 0, 0
    M.events = {}

    build_turbines()
    seed_rose()
    M.rebuild_hist()

    --[[把"今天零点到现在"已经发出来的电补进统计
如果不补，开机那一刻 mwh=0 而 hour 已经是 9.43 小时，容量系数会显示 0%，
收益 0 元，底部四格全是零 —— 中控室的人第一眼就会认为系统坏了。
补法就是把 96 点曲线里已经过去的那一段按 15 分钟做梯形积分。]]
    local idx = M.now_index()
    local mwh, peak = 0, 0
    for k = 1, idx do
        local p = M.hist.meas[k] or 0
        mwh = mwh + p * 0.25
        if p > peak then peak = p end
    end
    M.today.mwh = mwh
    M.today.peak = peak

    M.log_event(1, "集控系统启动，12 台机组开始上送数据")
    M.settle(0, true)
    log.info("wind", string.format("数据引擎启动 hour=%.2f 风速=%.1f", M.state.hour, M.state.wind))
end

-- ==================== 尾流 ====================
--[[按当前风向给每台机算有效风速
风向 dir 是"风从哪来"，所以气流方向是 dir + 180。
把机位投影到这个方向上，已经在上游挡着的机组越多，本机折减越大。
]]
local function apply_wake(v)
    local a = math.rad(M.state.dir)
    local ux, uy = -math.sin(a), -math.cos(a)   -- 气流方向（东分量, 北分量）
    local t = M.turbines
    for i = 1, M.N do
        local ti = t[i]
        local pi = ti.px * ux + ti.py * uy
        local ahead = 0
        for j = 1, M.N do
            if j ~= i then
                local tj = t[j]
                local pj = tj.px * ux + tj.py * uy
                -- 上游 = 投影更小（更靠近来风侧）；横向偏差 < 0.55km 才算被挡
                if pj < pi then
                    local dx = (tj.px - ti.px) - (pj - pi) * ux
                    local dy = (tj.py - ti.py) - (pj - pi) * uy
                    if dx * dx + dy * dy < 0.55 * 0.55 then ahead = ahead + 1 end
                end
            end
        end
        local loss = math.min(M.cfg.wake_max, M.cfg.wake * ahead)
        ti.weff = v * (1 - loss)
        ti.wind = v
    end
end

-- ==================== 单步结算 ====================
--[[结算当前时刻的机组出力 / 状态 / 全场指标
@param number dth 推进的仿真小时数
@param boolean force 强制重算（开机第一帧）
]]
function M.settle(dth, force)
    local s, cfg = M.state, M.cfg
    apply_wake(s.wind)

    local total, online = 0, 0
    for i = 1, M.N do
        local t = M.turbines[i]

        -- 故障倒计时（仿真秒）
        if t.fault_t > 0 then
            t.fault_t = t.fault_t - dth * 3600
            if t.fault_t <= 0 then
                t.fault_t = 0
                t.status = 0
                M.log_event(1, t.name .. " 故障复位，重新并网")
            end
        end

        local st = t.status
        if t.fault_t > 0 then
            st = 2
        elseif t.stop then
            st = 3
        elseif t.weff < cfg.cut_in or t.weff >= cfg.cut_out then
            st = 1
        else
            st = 0
        end
        t.status = st

        local p = 0
        if st == 0 then p = pcurve(t.weff, t.cap) end
        t.power = p
        t.curt = false

        -- 转速：切入附近慢慢起转，接近额定时满速
        if st == 0 then
            t.rpm = clamp(4.5 + t.weff * 0.85, 4.5, 14.8)
        else
            t.rpm = t.rpm * 0.9
            if t.rpm < 0.3 then t.rpm = 0 end
        end
        -- 桨距角：额定以上开始变桨限功率
        t.pitch = (t.weff > cfg.rated) and ((t.weff - cfg.rated) * 1.7) or 0
        -- 齿轮箱温度：出力越大越热，停机后缓慢回落
        local target = 44 + (p / t.cap) * 24 + 0.8 * math.sin(s.sim_t * 0.4 + i)
        t.temp = t.temp + (target - t.temp) * math.min(1, dth * 3 + 0.02)

        if st ~= 2 and st ~= 3 then online = online + 1 end
        total = total + p
    end

    -- 限电：按比例压出力，差额记损失
    if s.curtail_limit > 0 and total > s.curtail_limit and total > 0.01 then
        local k = s.curtail_limit / total
        local cut = 0
        for i = 1, M.N do
            local t = M.turbines[i]
            if t.power > 0 then
                local np = t.power * k
                cut = cut + (t.power - np)
                t.power = np
                t.curt = true
            end
        end
        total = s.curtail_limit
        M.today.loss = M.today.loss + cut * dth
    end

    s.power = total
    s.online = online
    s.avail = online / M.N * 100
    if total > M.today.peak then M.today.peak = total end

    -- 在今日曲线上钉一格"现在"的真实读数
    if force or (dth and dth > 0) then
        M.hist.meas[M.now_index()] = total
    end

    -- 风向玫瑰累积：哪个方位吹得久，哪一瓣就长
    local _, bin = M.compass(s.dir)
    M.rose.freq[bin] = M.rose.freq[bin] + dth
    M.rose.spd[bin] = M.rose.spd[bin] * 0.985 + s.wind * 0.015
end

-- ==================== 推进 ====================
local was_curt_auto = false   -- 低谷限电窗口是否已经记录过事件
local gust_on = false

--[[主推进：dt 是真实秒，speed 是仿真倍率（默认 60：1 秒 = 60 秒）]]
function M.tick(dt, speed)
    local s, cfg = M.state, M.cfg
    speed = speed or 60
    s.sim_t = s.sim_t + dt
    local dth = dt * speed / 3600
    s.hour = s.hour + dth

    if s.hour >= 24 then
        s.hour = s.hour - 24
        M.log_event(1, "跨天，今日发电量已归档")
        M.today.mwh, M.today.peak = 0, 0
        M.today.loss, M.today.faults = 0, 0
        M.rebuild_hist()
    end

    -- 风速：天气尺度 + 阵风
    local base = wind_at(s.hour)
    s.gust = s.gust * 0.96 + math.sin(s.sim_t * 0.9) * 0.05
    s.wind = clamp(base + s.gust, 0, 32)

    -- 风向：缓慢转动，风向变了尾流分布就变了
    s.dir = (315 + 26 * math.sin(s.sim_t * 0.004) + 9 * math.sin(s.sim_t * 0.017)) % 360

    -- 阵风预警（边沿触发，不刷屏）
    if s.wind > 16 and not gust_on then
        gust_on = true
        M.log_event(2, string.format("阵风 %.1fm/s，机组开始降容", s.wind))
    elseif s.wind < 14 and gust_on then
        gust_on = false
        M.log_event(1, "阵风过境，机组恢复满发")
    end

    -- 夜间低谷限电窗口（2:00 - 3:20），模拟电网调峰
    local in_window = (s.hour >= 2.0 and s.hour < 3.33)
    if in_window and not was_curt_auto and not s.curt then
        was_curt_auto = true
        M.set_curtail(true, true)
    elseif not in_window and was_curt_auto then
        was_curt_auto = false
        if s.curt and s.curt_auto then M.set_curtail(false, true) end
    end

    -- 随机故障：一天两三次的量级
    if rnd() < 0.00014 then
        local i = math.floor(rnd() * M.N) + 1
        local t = M.turbines[i]
        if t.status == 0 and t.fault_t == 0 and not t.stop then
            t.fault_t = 150 + rnd() * 150
            M.today.faults = M.today.faults + 1
            M.log_event(3, t.name .. " 变桨系统故障停机")
        end
    end

    M.settle(dth, false)
    M.today.mwh = M.today.mwh + s.power * dth
end

-- ==================== 外部操作 ====================
--[[调度限电开关
@param boolean on 是否限电
@param boolean auto true = 低谷窗口自动触发（解限时不覆盖人工设置的限电）
]]
function M.set_curtail(on, auto)
    local s = M.state
    if on then
        if s.curt then return false end
        s.curt = true
        s.curtail_limit = M.NCAP * M.cfg.curt_ratio
        s.curt_auto = auto and true or false
        M.log_event(2, string.format("调度下发限电指令 %.0fMW", s.curtail_limit))
    else
        if not s.curt then return false end
        s.curt = false
        s.curtail_limit = 0
        s.curt_auto = false
        M.log_event(1, "限电解除，机组恢复自由发电")
    end
    M.settle(0, false)
    return true
end

function M.toggle_curtail()
    return M.set_curtail(not M.state.curt, false)
end

--[[手动停机 / 复机（检修挂牌）
故障机点一下是"复位"，运行机点一下是"挂牌停机"。
]]
function M.toggle_turbine(i)
    local t = M.turbines[i]
    if not t then return nil, "无此机组" end
    if t.fault_t > 0 then
        t.fault_t = 0
        t.status = 0
        M.log_event(1, t.name .. " 人工复位，重新并网")
        M.settle(0, false)
        return "reset"
    end
    t.stop = not t.stop
    if t.stop then
        M.log_event(2, t.name .. " 检修挂牌停机")
    else
        M.log_event(1, t.name .. " 检修结束，恢复并网")
    end
    M.settle(0, false)
    return t.stop and "stop" or "start"
end

-- ==================== 派生指标 ====================
function M.cost()
    return M.today.mwh * 1000 * M.cfg.price     -- 元
end

-- 减排：MWh * 1000kWh * 0.581kg/kWh / 1000 = MWh * 0.581 吨
function M.co2_ton()
    return M.today.mwh * M.cfg.co2
end

-- 容量系数：实际发电 / (装机 * 已过小时数)
function M.cf()
    local h = math.max(0.5, M.state.hour)
    return M.today.mwh / (M.NCAP * h) * 100
end

function M.count_status(st)
    local n = 0
    for i = 1, M.N do
        if M.turbines[i].status == st then n = n + 1 end
    end
    return n
end

function M.now_index()
    local i = math.floor(M.state.hour / 24 * M.NPT) + 1
    return clamp(i, 1, M.NPT)
end

function M.clock_str()
    return hhmm(M.state.hour)
end

return M
