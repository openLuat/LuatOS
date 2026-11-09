--[[
@module  cold_data
@summary 冷链温控数据引擎（8 温区温度仿真 + 压缩机负载 + 事件流 + 24h 历史）
@version 1.0
@date    2026.11.08

=== 这一层负责什么 ===
界面只读 M.zones / M.state / M.today / M.events 这些字段，**不自己算温度**。
接真实采集时（Modbus 温湿度模块 / 冷库控制器 / MQTT 网关）按同样字段往里写值，
UI 一行都不用改：

  M.zones[i].temp    当前温度 C（浮点，负数表示零下）
  M.zones[i].door    true = 库门开着
  M.zones[i].status  0 正常 / 1 接近阈值 / 2 超温
  M.state.comp       压缩机负载 0..100（%）
  M.state.avg        所有温区平均温度 C
  M.state.hour       当前时刻 0..24（小数）

=== 仿真模型 ===
每个温区是一个"一阶惯性"：
  库门关：温度按 0.9 的速率被制冷拉回设定值；
  库门开：外界热量进入，按 (环境温度 - 库温) * 0.55 抬升；
  除霜中：蒸发器停止制冷，温度额外 +0.9/小时往上顶。
环境温度按一天的正弦变化（凌晨 22C、午后 30C），所以白天开门对温度的影响更大 ——
这正是真实现场"下午最容易超温"的原因。

压缩机负载 = 各温区制冷需求的加权平均：
温度高于设定越多，需求越大。四个冷冻区和四个冷藏区权重不同（冷冻更吃功率）。

事件流不是"定时写一条"，而是**状态边沿**：
超温开始 / 恢复、门开超时、除霜开始 / 结束、手动操作 —— 一天几十条，
面板上永远只看得到最近 6 条，值班的人一眼扫完就知道刚才发生了什么。
]]

local M = {}

-- ==================== 配置 ====================
M.cfg = {
    ambient_day   = 30.0,   -- 午后环境温度 C
    ambient_night = 22.0,   -- 凌晨环境温度 C
    door_warn_sec = 90,     -- 库门连续开启超过这么久的"仿真秒"就报警
    kwh_full      = 24.0,   -- 压缩机 100% 负载运行 1 小时的耗电 kWh
    price         = 0.78,   -- 平均电价 元/度（用来算今日电费）
    co2           = 0.581,  -- 碳排放因子 kg/kWh
}

--[[温区表
tol   允许偏差 C：超出 target±tol 记为"接近阈值"，超出 target±2*tol 记为超温
color 该温区在矩阵里的专属色（曲线 / 事件流沿用）
]]
M.zones = {
    { id = "f1", name = "冷冻 A",  target = -18.0, tol = 1.5, weight = 1.30, color = 0x3FC8FF, product = "冻肉" },
    { id = "f2", name = "冷冻 B",  target = -22.0, tol = 1.5, weight = 1.20, color = 0x5FA8FF, product = "冻品" },
    { id = "q1", name = "速冻库",  target = -30.0, tol = 2.0, weight = 1.60, color = 0x9BE8FF, product = "速冻面点" },
    { id = "c1", name = "冷藏 A",  target = 4.0,   tol = 1.2, weight = 0.85, color = 0x33D69F, product = "乳品" },
    { id = "c2", name = "冷藏 B",  target = 2.0,   tol = 1.2, weight = 0.85, color = 0x2ED3C4, product = "鲜肉" },
    { id = "v1", name = "果蔬库",  target = 8.0,   tol = 1.5, weight = 0.75, color = 0xFFA640, product = "蔬果" },
    { id = "v2", name = "缓冲间",  target = 0.0,   tol = 1.8, weight = 0.60, color = 0x9C7BFF, product = "中转" },
    { id = "d1", name = "预冷间",  target = 6.0,   tol = 1.5, weight = 0.70, color = 0x7ED0FF, product = "预冷" },
}
M.NZONE = #M.zones

-- ==================== 状态 ====================
M.state = {
    hour = 9.0, comp = 0, avg = 0, sim_t = 0, ambient = 25,
}

M.today = {
    kwh = 0,      -- 今日累计用电
    peak = 0,     -- 压缩机负载峰值 %
    doors = 0,    -- 今日开门次数
    over = 0,     -- 今日超温次数
    save = 12.5,  -- 节能率 %（相对去年同期）
}

-- 24 小时历史（96 点，15 分钟一格），按温区下标存
M.NPT = 96
M.hist = {}

-- 事件流（1 = 最新）
M.events = {}
M.MAX_EVENT = 24

-- ==================== 工具 ====================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
M.clamp = clamp

-- 固定种子线性同余发生器：每次开机生成的"历史扰动"完全一样，
-- 曲线可复现，改参数前后能直接对比
local seed = 20261108
local function rnd()
    seed = (seed * 16807) % 2147483647
    return seed / 2147483647
end

local function gauss(x, c0, s)
    local d = (x - c0) / s
    return math.exp(-d * d)
end

-- 环境温度：凌晨最低、午后最高
local function ambient_at(h)
    return (M.cfg.ambient_day + M.cfg.ambient_night) / 2
        + (M.cfg.ambient_day - M.cfg.ambient_night) / 2 * math.sin((h - 9) / 24 * math.pi * 2)
end
M.ambient_at = ambient_at

-- 时刻字符串
local function hhmm(h)
    local hh = math.floor(h) % 24
    local mm = math.floor((h - math.floor(h)) * 60)
    return string.format("%02d:%02d", hh, mm)
end
M.hhmm = hhmm

-- ==================== 事件流 ====================
--[[写一条事件
@param number level 1 提示 / 2 警告 / 3 报警
@param string text 事件描述（屏上只有一行，务必简短）
]]
function M.log_event(level, text)
    local e = { t = hhmm(M.state.hour), level = level, text = text, ts = M.state.sim_t }
    table.insert(M.events, 1, e)
    for i = #M.events, M.MAX_EVENT + 1, -1 do M.events[i] = nil end
    return e
end

-- 确认一条（把 level 降成 0，界面上变成灰色带勾）
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

-- ==================== 温区初始化 ====================
function M.init()
    local ok, d = pcall(os.date, "*t")
    local h = 9.0
    if ok and type(d) == "table" and d.hour then h = d.hour + (d.min or 0) / 60 end
    M.state.hour = h
    M.state.ambient = ambient_at(h)

    -- 初始温度：设定值附近的小偏置，看起来像"已经稳定运行很久"
    for i = 1, M.NZONE do
        local z = M.zones[i]
        z.temp = z.target + (rnd() - 0.5) * z.tol * 0.9
        z.door = false
        z.door_t = 0
        z.defrost = 0
        z.status = 0
        z.duty = 0
    end

    M.rebuild_hist()
    M.log_event(1, "系统启动，八个温区开始采集")
    M.settle(0, true)
    log.info("cold", string.format("数据引擎启动 hour=%.2f 温区=%d", M.state.hour, M.NZONE))
end

--[[重建 24h 历史曲线
按"该温区的日负荷节律"生成：装卸货集中在 7-9 点、13-15 点、19-21 点，
这三次开门会让温度出现可见的尖峰 —— 曲线本身就该讲故事。]]
function M.rebuild_hist()
    local step = 24 / M.NPT
    for i = 1, M.NZONE do
        local z = M.zones[i]
        local arr = M.hist[i]
        if not arr then arr = {}; M.hist[i] = arr end
        for k = 1, M.NPT do
            local h = (k - 1) * step
            local door = 0.55 * gauss(h, 8.0, 1.1) + 0.85 * gauss(h, 14.0, 1.3) + 0.60 * gauss(h, 19.8, 1.4)
            local amb = (ambient_at(h) - 20) / 10
            -- 温度 = 设定值 + 开门扰动 + 环境热负荷，再加一点固定相位噪声
            local v = z.target + z.tol * (door * 1.35 + amb * 0.30)
                + z.tol * 0.16 * math.sin(h * 2.7 + i)
            arr[k] = v
        end
    end
end

-- ==================== 单步推进 ====================
--[[结算当前时刻的温度 / 负载 / 状态
@param number dth 推进的仿真小时数
@param boolean force 强制重算（开机第一帧用）
]]
function M.settle(dth, force)
    local s = M.state
    s.ambient = ambient_at(s.hour)
    local sum, wsum, total = 0, 0, 0

    for i = 1, M.NZONE do
        local z = M.zones[i]
        local dt = dth or 0

        if dt > 0 then
            -- 制冷机被人手动停掉时不再拉回，温度只会被外界推着往上走
            local pull = z.comp_off and 0 or ((z.target - z.temp) * 0.95)
            local heat = 0
            if z.door then
                -- 门开着：外界热空气灌进来，温差越大进得越快
                heat = heat + (s.ambient - z.temp) * 0.55
            end
            if z.defrost > 0 then
                heat = heat + 1.4                             -- 除霜时蒸发器不制冷
                z.defrost = z.defrost - dt
                if z.defrost <= 0 then
                    z.defrost = 0
                    M.log_event(1, z.name .. " 除霜结束")
                end
            end
            -- 慢抖动：真实温度不会是一条直线
            local noise = 0.9 * math.sin(s.sim_t * 0.7 + i * 2.1) * 0.35
            z.temp = z.temp + (pull + heat + noise) * dt * 6.0

            if z.door then
                z.door_t = z.door_t + dt * 3600
                if z.door_t > M.cfg.door_warn_sec and not z.door_warned then
                    z.door_warned = true
                    M.log_event(2, z.name .. " 库门开启超时")
                end
            end
        end

        -- 状态分级：正常 / 接近阈值 / 超温
        local dev = math.abs(z.temp - z.target)
        local st = 0
        if dev > z.tol * 2 then st = 2
        elseif dev > z.tol then st = 1 end
        if st == 2 and z.status ~= 2 then
            M.today.over = M.today.over + 1
            M.log_event(3, string.format("%s 超温 %.1fC", z.name, z.temp))
        elseif st == 0 and z.status == 2 then
            M.log_event(1, z.name .. " 温度已恢复")
        end
        z.status = st

        -- 制冷需求：偏离越大越吃力；门开 / 除霜时需求拉满
        local duty = clamp(0.35 + (z.temp - z.target) / (z.tol * 3) * 0.5, 0, 1)
        if z.door or z.defrost > 0 then duty = clamp(duty + 0.35, 0, 1) end
        if z.comp_off then duty = 0 end
        z.duty = duty
        sum = sum + z.temp
        total = total + duty * z.weight
        wsum = wsum + z.weight
    end

    s.avg = sum / M.NZONE
    s.comp = clamp(total / wsum * 100, 0, 100)

    -- 在今日曲线上钉一格"现在"的真实读数
    if force or (dth and dth > 0) then
        local idx = M.now_index()
        for i = 1, M.NZONE do
            M.hist[i][idx] = M.zones[i].temp
        end
    end

    if s.comp > M.today.peak then M.today.peak = s.comp end
end

--[[主推进：dt 是真实秒，speed 是仿真倍率（默认 40：1 秒 = 40 秒）]]
function M.tick(dt, speed)
    local s = M.state
    speed = speed or 40
    s.sim_t = s.sim_t + dt
    local dth = dt * speed / 3600        -- 仿真小时
    s.hour = s.hour + dth

    if s.hour >= 24 then
        s.hour = s.hour - 24
        M.log_event(1, "跨天，今日累计已归档")
        M.today.kwh, M.today.peak = 0, 0
        M.today.doors, M.today.over = 0, 0
        M.rebuild_hist()
    end

    -- 自动开门：装卸货时段更容易开门，随机但用固定种子，节奏可复现
    for i = 1, M.NZONE do
        local z = M.zones[i]
        if not z.door then
            local p = 0.004 + 0.02 * (gauss(s.hour, 8.0, 1.2) + gauss(s.hour, 14.0, 1.4)
                + gauss(s.hour, 19.8, 1.5))
            z.door_t = 0
            z.door_warned = false
            if rnd() < p then
                z.door = true
                z.door_hold = 20 + rnd() * 70
                M.today.doors = M.today.doors + 1
                M.log_event(1, z.name .. " 库门开启")
            end
        else
            z.door_hold = (z.door_hold or 40) - dt * speed
            if z.door_hold <= 0 then
                z.door = false
                M.log_event(1, z.name .. " 库门关闭")
            end
        end
    end

    M.settle(dth, false)
    M.today.kwh = M.today.kwh + s.comp / 100 * M.cfg.kwh_full * dth
end

-- ==================== 外部操作 ====================
-- 手动开门 / 关门（演示与现场测试都用它）
function M.toggle_door(i)
    local z = M.zones[i]
    if not z then return nil end
    z.door = not z.door
    if z.door then
        z.door_t = 0
        z.door_warned = false
        z.door_hold = 45
        M.today.doors = M.today.doors + 1
        M.log_event(2, z.name .. " 手动开门")
    else
        M.log_event(1, z.name .. " 手动关门")
    end
    M.settle(0, false)
    return z.door
end

-- 触发一次除霜（实际柜子上是定时除霜，这里给值班的人手动补一次）
function M.start_defrost(i)
    local z = M.zones[i]
    if not z then return nil end
    if z.defrost > 0 then return false end
    z.defrost = 0.22            -- 仿真小时，约 13 分钟
    M.log_event(1, z.name .. " 开始除霜")
    return true
end

function M.toggle_comp(i)
    local z = M.zones[i]
    if not z then return nil end
    z.comp_off = not z.comp_off
    M.log_event(z.comp_off and 2 or 1, z.name .. (z.comp_off and " 制冷机停止" or " 制冷机恢复"))
    return not z.comp_off
end

-- 设备总数 / 报警设备数（顶栏三个状态点用）
function M.count_status(st)
    local n = 0
    for i = 1, M.NZONE do
        if M.zones[i].status == st then n = n + 1 end
    end
    return n
end

-- ==================== 派生指标 ====================
function M.cost()
    return M.today.kwh * M.cfg.price
end

function M.co2()
    return M.today.kwh * M.cfg.co2
end

-- 当前时刻在今日曲线里的下标
function M.now_index()
    local i = math.floor(M.state.hour / 24 * M.NPT) + 1
    return clamp(i, 1, M.NPT)
end

-- 时钟字符串（演示态下按仿真时间走，有 RTC 时开机就跟真实时间）
function M.clock_str()
    return hhmm(M.state.hour)
end

return M
