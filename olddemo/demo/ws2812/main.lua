--[[
@module  main
@summary WS2812 灯带演示：64 灯 RGB 三色循环（ws2812 库 / GPIO 模式 / GPIO12）
@version 1.0
@date    2026.11.10

=== 硬件连接 ===
  DIN  -> GPIO12
  VCC  -> 5V（64 颗全白满亮度峰值电流可达 3.8A 左右，务必确认电源余量）
  GND  -> 与模块共地

=== 演示内容 ===
  1. 上电初始化 ws2812 句柄，设置 GPIO 模式时序 T0H/T0L/T1H/T1L = 15/45/45/15
  2. 上电先清屏，避免 DIN 杂波被首颗灯误锁存（开机鬼影）
  3. 用 sys.taskInit 起一个任务，每 5 秒切换一次颜色：红 -> 绿 -> 蓝 -> 红 ...
]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ws2812_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

-- ==================== 可调参数 ====================
local LED_COUNT = 64        -- 灯珠数量
local LED_GPIO  = 12        -- DIN 数据引脚

-- WS2812B 时序，按实测值填写
-- 注意：GPIO 模式下的单位由底层芯片决定，各 BSP 实现差异较大，
--       这里按 bit0H=15 bit0L=45 bit1H=45 bit1L=15 原样下发。
local T0H, T0L, T1H, T1L = 15, 45, 45, 15	--Air160X的配置

-- 亮度系数 0~255。64 颗灯满亮度全白电流很大，默认压到 100 保守一些，
-- 电源与灯带确认能扛住后可改为 255。
local BRIGHT    = 100
local STEP_MS   = 1000      -- 每次循环的间隔，5 秒

-- RGB 循环色表（按顺序播放）
local COLORS = {
    { name = "红", r = 255, g = 0,   b = 0   },
    { name = "绿", r = 0,   g = 255, b = 0   },
    { name = "蓝", r = 0,   g = 0,   b = 255 },
}

-- ==================== 句柄初始化 ====================
-- ws2812.create(mode, count, pin)：mode 选 GPIO 表示用普通 GPIO 位翻转驱动
local leds = ws2812.create(ws2812.GPIO, LED_COUNT, LED_GPIO)
if not leds then
    log.error("ws2812b", "ws2812.create 失败，请确认固件已开启 ws2812 与 GPIO 组件")
else
    -- 下发时序：T0H / T0L / T1H / T1L
    ws2812.args(leds, T0H, T0L, T1H, T1L)
    log.info("ws2812b", "句柄创建成功", "GPIO", LED_GPIO, "灯数", LED_COUNT,
             "时序", T0H, T0L, T1H, T1L)

    -- 上电清屏：创建后立刻把显存清零并发送一次完整帧
    -- 此时 DIN 电平已稳定，能可靠覆盖灯珠内随机锁存的数据
    for i = 0, LED_COUNT - 1 do
        ws2812.set(leds, i, 0, 0, 0)
    end
    ws2812.send(leds)
end

-- 亮度缩放：把 0~255 的原始分量按 BRIGHT 等比压缩
local function scale(v)
    if BRIGHT >= 255 then return v end
    return math.floor(v * BRIGHT / 255 + 0.5)
end

-- ==================== 演示任务 ====================
local function ws2812b_demo_task()
    if not leds then
        log.error("ws2812b", "句柄无效，任务退出")
        return
    end

    -- 等 100ms，让电源与 DIN 电平彻底稳定后再开始刷帧
    sys.wait(100)

    local idx = 1
    while true do
        local c = COLORS[idx]
        local r, g, b = scale(c.r), scale(c.g), scale(c.b)

        -- 1) 整条灯带写同一颜色（只写显存，不发送）
        for i = 0, LED_COUNT - 1 do
            ws2812.set(leds, i, r, g, b)
        end
        -- 2) 一次性推送到灯带，一帧 64*24=1536 bit，耗时约 2ms（临界区内完成）
        ws2812.send(leds)
        log.info("ws2812b", "循环颜色", c.name, string.format("#%02X%02X%02X", r, g, b))

        -- 3) 指向下一个颜色，循环播放
        idx = idx % #COLORS + 1

        -- 4) 保持 5 秒
        sys.wait(STEP_MS)
    end
end

sys.taskInit(ws2812b_demo_task)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
