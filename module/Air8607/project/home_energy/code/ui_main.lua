--[[
@module  ui_main
@summary 家庭能源监测面板 - UI 启动与主循环
@version 1.0
@date    2026.10.26

=== 这一层只做三件事 ===
1、build()：初始化数据引擎，搭出整块面板，绑定触摸；
2、run()：以 33ms 周期推进"仿真时间 + 界面刷新"；
3、把"数据"和"界面"两个世界的节拍对齐。

=== 为什么主循环不用 sys.waitUntil 之类的同步原语 ===
这块屏是纯展示型产品，没有需要抢占的实时事件：
触摸回调由 LVGL 在 airui 自己的 timer 里分发，不需要我们调度；
数据源（未来接 MQTT / Modbus 电表）也是"来了就写字段"的模式。
所以一个固定节拍的循环足够，简单、可预测，也不会因为某个分支
偶尔慢一帧就把整个界面的时间基准拖歪 —— 每帧都重新读一次时钟算 dt。
]]

local T = require "theme"
local data = require "energy_data"
local dash = require "dashboard"

local M = {}

--[[毫秒时钟
优先 mcu.ticks2(1)：底层是 64 位计数，返回 (千秒, 毫秒余数)，永远不会回绕。
mcu.ticks() 是 32 位、会回绕（回绕后 Lua 侧还是负数），
回绕那一刻算出来的 dt 是负的，仿真时间被"倒拨"，曲线会倒退一小段，肉眼可见。
mcu.ticks() + mcu.hz() 只作降级，hz 通常 1000 但不是所有固件都保证。]]
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
        -- 首帧、时钟回绕或长时间被抢占时（比如刷屏卡了一下），
        -- dt 会异常大：直接按一帧处理，避免仿真时间"跳"一大截
        if dt <= 0 or dt > 0.5 then dt = T.perf.frame_ms / 1000 end

        data.tick(dt, T.perf.demo_speed)
        dash.update(dt)

        sys.wait(T.perf.frame_ms)
    end
end

return M
