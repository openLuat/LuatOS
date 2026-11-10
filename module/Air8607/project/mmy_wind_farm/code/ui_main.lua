--[[
@module  ui_main
@summary 北岭风电场 - UI 启动与主循环
@version 1.0
@date    2026.11.09

=== 这一层只做四件事 ===
1、build()：初始化数据引擎，搭出整块面板；
2、run()：以 33ms 周期推进"仿真时间 + 分区刷新"；
3、报警联动语音：事件流出现新的 2 级以上事件时播一句（走 voice.auto，有冷却）；
4、把"数据"和"界面"两个世界的节拍对齐。

=== 为什么主循环不用事件驱动 ===
这是常亮展示型看板，没有需要抢占的实时事件：
触摸由 LVGL 在 airui 自己的 timer 里分发；真实采集接进来以后也是"来了就写字段"。
所以固定节拍就够了 —— 每帧重新读一次时钟算 dt，不累计误差，也不会因为某一帧
偶尔慢了就把时间基准拖歪。
]]

local T = require "theme"
local data = require "wind_data"
local dash = require "dashboard"
local voice = require "voice"

local M = {}

--[[毫秒时钟
优先 mcu.ticks2(1)：底层是 64 位计数，返回 (千秒, 毫秒余数)，永远不会回绕。
mcu.ticks() 是 32 位、会回绕，回绕那一刻算出来的 dt 是负数，仿真时间被倒拨，
曲线会倒退一小段，肉眼可见。
]]
local function now_ms()
    if mcu and mcu.ticks2 then
        local hi, lo = mcu.ticks2(1)
        if hi and lo then return hi * 1000000 + lo end
    end
    if mcu and mcu.ticks and mcu.hz then
        local hz = mcu.hz()
        if hz and hz > 0 then return mcu.ticks() * 1000 / hz end
    end
    return os.clock() * 1000
end

local last_alarm_ts = -1

--[[报警语音联动
只看事件流最新一条：如果是 2 级以上且时间戳是新的，就播报。
用 sim_t 而不是 os.time 判断新旧：事件时间戳由数据引擎自己维护，跨天也不会乱。
]]
local function watch_alarm()
    local e = data.events[1]
    if not e or e.ts == last_alarm_ts then return end
    last_alarm_ts = e.ts
    if e.level >= 2 then
        voice.auto(e.text)
    end
end

function M.build()
    -- 数据引擎先起：dashboard.build 里的机组砖块要按 data.turbines 建
    data.init()
    dash.build()
end

function M.run()
    local last = now_ms()
    while true do
        local t = now_ms()
        local dt = (t - last) / 1000
        last = t
        -- 首帧 / 时钟异常 / 被长时间抢占（比如刷屏卡了一下）时 dt 会很大：
        -- 按一帧处理，避免仿真时间跳一大截（风速和功率会瞬间冲高再回落）
        if dt <= 0 or dt > 0.5 then dt = T.perf.frame_ms / 1000 end

        dash.update(dt)     -- 内部推进数据引擎 + 分区重绘
        watch_alarm()

        sys.wait(T.perf.frame_ms)
    end
end

return M
