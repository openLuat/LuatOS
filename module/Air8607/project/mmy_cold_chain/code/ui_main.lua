--[[
@module  ui_main
@summary 冷链温控中枢 - UI 启动与主循环
@version 1.0
@date    2026.11.08

=== 这一层只做四件事 ===
1、build()：初始化数据引擎，搭出整块面板，绑定触摸；
2、run()：以 33ms 周期推进"仿真时间 + 界面刷新"；
3、报警联动语音：出现新的 2 级以上事件时播一句（走 voice.auto，有 10 秒冷却）；
4、把"数据"和"界面"两个世界的节拍对齐。

=== 为什么主循环不用事件驱动 ===
这块屏是纯展示型产品，没有需要抢占的实时事件：
触摸回调由 LVGL 在 airui 自己的 timer 里分发，不需要我们调度；
数据源（未来接 Modbus 温度模块 / 冷库控制器）也是"来了就写字段"的模式。
所以一个固定节拍的循环足够，简单、可预测，也不会因为某个分支偶尔慢一帧
就把整个界面的时间基准拖歪 —— 每帧都重新读一次时钟算 dt。
]]

local T = require "theme"
local data = require "cold_data"
local dash = require "dashboard"
local voice = require "voice"

local M = {}

--[[毫秒时钟
优先 mcu.ticks2(1)：底层是 64 位计数，返回 (千秒, 毫秒余数)，永远不会回绕。
mcu.ticks() 是 32 位、会回绕（回绕后 Lua 侧还是负数），回绕那一刻算出来的 dt
是负的，仿真时间被"倒拨"，曲线会倒退一小段，肉眼可见。
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

local last_alarm_ts = 0

--[[报警语音联动
事件流里最新一条如果是 2 级以上、且是"刚发生"的，就播报。
用 sim_t 而不是 os.time 判断新旧：事件时间戳由数据引擎自己维护，跨天也不乱。
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
    data.init()
    dash.build()
end

function M.run()
    local last = now_ms()
    while true do
        local t = now_ms()
        local dt = (t - last) / 1000
        last = t
        -- 首帧、时钟回绕或长时间被抢占（刷屏卡了一下）时 dt 会异常大：
        -- 直接按一帧处理，避免仿真时间"跳"一大截
        if dt <= 0 or dt > 0.5 then dt = T.perf.frame_ms / 1000 end

        data.tick(dt, T.perf.demo_speed)
        watch_alarm()
        dash.update(dt)

        sys.wait(T.perf.frame_ms)
    end
end

return M
