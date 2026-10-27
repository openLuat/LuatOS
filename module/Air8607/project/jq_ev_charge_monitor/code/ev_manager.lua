--[[
@module  ev_manager
@summary 充电桩状态机 + 完成停留计时 + 定时语音播报调度
@version 1.0
@date    2026.10.23

=== 状态模型 ===
  idle      空闲
  charging  充电中（soc 持续上升，驱动卡片的电池动画）
  done      充电完成（充满 / 预充金额用完），开始停留计时

=== 计时基准 ===
不用 sys.wait 累加（会漂移），用 mcu.ticks() 绝对时间差折算成秒：
  Air1603 主控约 20ms/tick（mcu.hz()==50），PC 模拟器 hz()==1 且 ticks 本身就是毫秒。
统一在 now_s() 里处理，两个平台都算得对。

=== 定时播报规则 ===
1. 任一桩进入 done，立即播报一次「XX号充电桩充电完成，请及时驶离，超时将产生费用」。
2. 勾选「定时播报」后，从完成时刻起每 N 分钟重复一次，直到车辆驶离。
3. 车辆驶离（done -> idle）后计时归零，该桩不再播报。
4. 中途修改 N：对已完成的桩重新从"现在"起算 N 分钟。

=== 真机对接 ===
auto_demo 置 false，由充电桩通讯层调用 begin_charge() / set_soc() / finish() / leave()，
UI 层无需改动。
]]
local cfg = require "ev_config"
local voice = require "ev_voice"

local M = {}

M.piles = {}
M.timer_on = false                       -- 定时播报总开关
M.interval_min = cfg.DEFAULT_INTERVAL_MIN
M.auto_demo = true                       -- 演示数据开关

local change_cb = nil
local tick_hz = 1000
local time_inited = false
local demo_acc = 0

-- ==================== 时间基准 ====================
local function init_time_once()
    if time_inited then return end
    time_inited = true
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        tick_hz = hz
        log.info("ev_manager", string.format("时间基准: mcu.hz()=%d, 每 tick 约 %.1f ms", hz, 1000 / hz))
    else
        tick_hz = 1000
        log.info("ev_manager", "时间基准: mcu.hz 不可用，按 1 tick = 1ms")
    end
end

--[[当前时间（秒，浮点）]]
function M.now_s()
    init_time_once()
    if mcu and mcu.ticks then
        return mcu.ticks() / tick_hz
    end
    return os.time()
end

local function notify(pile, action)
    if change_cb then
        local ok, err = pcall(change_cb, pile, action)
        if not ok then log.warn("ev_manager", "状态回调异常", err) end
    end
end

-- ==================== 初始化 ====================
local function new_pile(i)
    return {
        id = i,
        bay = cfg.bay_name(i),
        status = "idle",
        kw = 0,              -- 当前功率 kW
        kwh = 0,             -- 本次已充电量
        soc = 0,             -- 电量百分比（驱动电池图形）
        target_soc = 80,     -- 目标电量（充满判定）
        limit_kwh = 40,      -- 预充金额对应的电量上限
        reason = nil,        -- "full" 充满 / "limit" 金额用完
        start_s = nil,       -- 开始充电时刻
        done_s = nil,        -- 完成时刻（停留计时起点）
        next_say_s = nil,    -- 下一次定时播报时刻
        said = false,        -- 本次完成是否已播报
    }
end

--[[初始化 10 个桩位
@param table ctors 可选，按序号覆盖初始状态（演示用）
]]
function M.init(ctors)
    init_time_once()
    M.piles = {}
    for i = 1, cfg.PILE_COUNT do
        M.piles[i] = new_pile(i)
    end
    if ctors then
        for i, c in ipairs(ctors) do
            local p = M.piles[i]
            if p then
                p.status = c.status or p.status
                p.soc = c.soc or p.soc
                p.kwh = c.kwh or p.kwh
                p.kw = c.kw or p.kw
                p.target_soc = c.target_soc or p.target_soc
                p.limit_kwh = c.limit_kwh or p.limit_kwh
            end
        end
    end

    local now = M.now_s()
    for i = 1, cfg.PILE_COUNT do
        local p = M.piles[i]
        if p.status == "charging" then
            if not p.start_s then p.start_s = now - (i * 137) % 900 end
            if p.kw <= 0 then p.kw = 6.8 + (i % 3) * 0.9 end
            if p.soc <= 0 then p.soc = 30 end
            -- 已充电量与当前电量对齐，避免"42% 却已充 0 kWh"这种自相矛盾的显示
            if p.kwh <= 0 then p.kwh = p.limit_kwh * p.soc / 100 end
        elseif p.status == "done" then
            p.done_s = now - 95
            p.said = true          -- 开机不补播已完成的历史桩
            p.reason = "full"
            p.soc = 100
            p.kwh = p.limit_kwh
            if M.timer_on then
                p.next_say_s = now + M.interval_min * 60
            end
        end
    end
end

function M.on_change(cb)
    change_cb = cb
end

-- ==================== 状态迁移 ====================
--[[开始充电
@param number i 桩号（1 起）
@param table opts {soc,target_soc,limit_kwh,kw}
]]
function M.begin_charge(i, opts)
    local p = M.piles[i]
    if not p then return end
    opts = opts or {}
    p.status = "charging"
    p.soc = opts.soc or (8 + math.random(0, 25))
    p.target_soc = opts.target_soc or (80 + math.random(0, 15))
    p.limit_kwh = opts.limit_kwh or (18 + math.random(0, 20))
    p.kwh = 0
    p.kw = opts.kw or (6.5 + math.random() * 4)
    p.start_s = M.now_s()
    p.done_s = nil
    p.next_say_s = nil
    p.said = false
    p.reason = nil
    log.info("ev_manager", string.format("%s 开始充电 soc=%d%% 功率=%.1fkW",
        p.bay, math.floor(p.soc), p.kw))
    notify(p, "charging")
end

--[[外部推进电量（真机数据源用；演示模式由 tick 内部推进）]]
function M.set_soc(i, soc)
    local p = M.piles[i]
    if not p or p.status ~= "charging" then return end
    soc = math.max(0, math.min(100, soc or 0))
    if soc >= p.target_soc then
        M.finish(i, "full")
        return
    end
    p.soc = soc
    p.kwh = p.limit_kwh * soc / 100
    notify(p, "soc")
end

--[[充电完成
@param number i 桩号
@param string reason "full" 充满 / "limit" 预充金额用完
]]
function M.finish(i, reason)
    local p = M.piles[i]
    if not p or p.status ~= "charging" then return end
    p.status = "done"
    p.done_s = M.now_s()
    p.reason = reason or "full"
    p.kw = 0
    if p.reason == "full" then
        p.soc = p.target_soc
    else
        p.kwh = p.limit_kwh
    end
    p.said = false
    p.next_say_s = nil
    log.info("ev_manager", string.format("%s 充电完成（%s），开始停留计时",
        p.bay, p.reason == "full" and "充满" or "预充金额用完"))
    notify(p, "done")
    M.say_done(p)          -- 完成瞬间立即播报一次
end

--[[车辆驶离：停留计时归零，回到空闲]]
function M.leave(i)
    local p = M.piles[i]
    if not p or p.status ~= "done" then return end
    log.info("ev_manager", string.format("%s 车辆驶离，停留计时归零（停留 %d 秒）",
        p.bay, math.floor(M.stay_seconds(i))))
    p.status = "idle"
    p.soc = 0
    p.kwh = 0
    p.kw = 0
    p.done_s = nil
    p.next_say_s = nil
    p.start_s = nil
    p.said = false
    p.reason = nil
    notify(p, "idle")
end

--[[卡片点击：空闲->充电 / 充电->完成 / 完成->驶离（现场演示入口）]]
function M.toggle(i)
    local p = M.piles[i]
    if not p then return end
    if p.status == "idle" then
        M.begin_charge(i)
    elseif p.status == "charging" then
        M.finish(i, "full")
    else
        M.leave(i)
    end
end

-- ==================== 播报 ====================
--[[播报某桩的完成提示]]
function M.say_done(p)
    if p.said then return end
    p.said = true
    p.next_say_s = M.timer_on and (M.now_s() + M.interval_min * 60) or nil
    voice.say(string.format(cfg.TTS_DONE_FMT, p.id), "pile" .. p.id)
end

--[[定时播报开关]]
function M.set_timer(on)
    M.timer_on = on and true or false
    local now = M.now_s()
    for _, p in ipairs(M.piles) do
        if p.status == "done" then
            p.next_say_s = M.timer_on and (now + M.interval_min * 60) or nil
        end
    end
    log.info("ev_manager", "定时播报", M.timer_on and "开启" or "关闭", M.interval_min, "分钟")
end

--[[设置定时间隔（分钟）]]
function M.set_interval(min)
    min = math.max(cfg.MIN_INTERVAL_MIN, math.min(cfg.MAX_INTERVAL_MIN, math.floor(min or 1)))
    M.interval_min = min
    local now = M.now_s()
    for _, p in ipairs(M.piles) do
        if p.status == "done" and M.timer_on then
            p.next_say_s = now + min * 60
        end
    end
    log.info("ev_manager", "定时间隔调整为", min, "分钟")
    return min
end

local function check_timer(now)
    if not M.timer_on then return end
    for _, p in ipairs(M.piles) do
        if p.status == "done" then
            if not p.next_say_s then
                p.next_say_s = now + M.interval_min * 60
            elseif now >= p.next_say_s then
                p.next_say_s = now + M.interval_min * 60
                voice.say(string.format(cfg.TTS_DONE_FMT, p.id), "pile" .. p.id)
            end
        end
    end
end

-- ==================== 查询 ====================
--[[完成桩的停留秒数；非完成态返回 0]]
function M.stay_seconds(i)
    local p = M.piles[i]
    if not p or p.status ~= "done" or not p.done_s then return 0 end
    local s = M.now_s() - p.done_s
    if s < 0 then s = 0 end
    return s
end

--[[充电已进行秒数]]
function M.charge_seconds(i)
    local p = M.piles[i]
    if not p or p.status ~= "charging" or not p.start_s then return 0 end
    local s = M.now_s() - p.start_s
    if s < 0 then s = 0 end
    return s
end

--[[下一次定时播报倒计时秒数；无则返回 nil]]
function M.next_say_in(i)
    local p = M.piles[i]
    if not M.timer_on or not p or p.status ~= "done" or not p.next_say_s then return nil end
    local s = p.next_say_s - M.now_s()
    if s < 0 then s = 0 end
    return s
end

--[[第一个已完成待驶离的桩（底部状态行用）]]
function M.first_done()
    for _, p in ipairs(M.piles) do
        if p.status == "done" then return p end
    end
    return nil
end

-- 返回 空闲, 充电中, 已完成
function M.counts()
    local idle, charging, done = 0, 0, 0
    for _, p in ipairs(M.piles) do
        if p.status == "idle" then idle = idle + 1
        elseif p.status == "charging" then charging = charging + 1
        else done = done + 1 end
    end
    return idle, charging, done
end

-- ==================== 主循环 ====================
--[[推进演示数据 + 定时播报检查（由 main 定时调用）
@param number dt_s 距上次调用经过的秒数
]]
function M.tick(dt_s)
    local now = M.now_s()
    if M.auto_demo and dt_s and dt_s > 0 then
        demo_acc = demo_acc + dt_s
        if demo_acc >= 0.5 then
            local step = demo_acc
            demo_acc = 0
            for _, p in ipairs(M.piles) do
                if p.status == "charging" then
                    -- 电量与电量额度各自推进：约 90 秒走完 70% 电量、
                    -- 也约 90 秒走完预充额度，两种完成原因都会出现
                    p.soc = p.soc + step * 0.8
                    p.kwh = p.kwh + step * (p.limit_kwh / 90)
                    if p.soc >= p.target_soc then
                        M.finish(p.id, "full")
                    elseif p.kwh >= p.limit_kwh then
                        M.finish(p.id, "limit")
                    end
                end
            end
            -- 偶发自动开始充电（平均约 2 分钟一台），让界面持续有变化
            if math.random() < 0.004 then
                local idle = {}
                for _, p in ipairs(M.piles) do
                    if p.status == "idle" then idle[#idle + 1] = p end
                end
                if #idle > 0 then
                    M.begin_charge(idle[math.random(#idle)].id)
                end
            end
        end
    end
    check_timer(now)
end

return M
