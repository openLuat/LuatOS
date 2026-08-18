--[[
@module  ws2812_config
@summary WS2812 22×22 点阵公共配置（硬件参数、坐标映射、颜色工具、句柄初始化）
@version 1.1
@date    2026.08.17
@usage
适用产品：合宙 Air1780P / Air1780H / Air1780HV。
         灯板尺寸不是 22×22 时，请同步修改 LED_W / LED_H / LED_COUNT。

本文件由 main.lua 通过 require 自动加载，为各效果模块提供全局 WS2812 句柄与工具函数：
  - LED_W / LED_H / LED_COUNT / LED_GPIO  硬件参数
  - WS2812_CFG                            运行时配置（brightness / speed_ms）
  - WS2812_LEDS                           ws2812 句柄（创建失败为 nil）
  - ws2812_xy(x, y)                       蛇形逻辑坐标 → 物理 LED 编号
  - ws2812_hsv2rgb(h, s, v)               HSV → RGB888 整数
  - ws2812_rgb(r, g, b)                   RGB → 24bit 整数
  - ws2812_set(x, y, color)               按逻辑坐标点亮（写缓冲，不发送）
  - ws2812_fill(color)                    整片填充并立即发送
  - ws2812_clear()                        整片清屏（写缓冲，不发送）
  - ws2812_send()                         发送当前缓冲到灯板
]]

-- ==================== 硬件参数 ====================
-- 根据实际灯板修改这几个值即可适配其他尺寸
LED_W     = 22            -- 灯板列数（水平方向 LED 数量）
LED_H     = 22            -- 灯板行数（垂直方向 LED 数量）
LED_COUNT = LED_W * LED_H -- LED 总数 = 484
LED_GPIO  = 16            -- DIN 数据引脚接 Air1780P/H/HV 的 GPIO16（PIN97）

-- ==================== 运行时可调参数 ====================
-- 可通过串口命令 b=NNN / s=NNN 在运行时修改，无需重新烧录
WS2812_CFG = {
    brightness = 50,    -- 亮度 0~255。全白 255 时整机峰值电流约 25-30A，注意电源
    speed_ms   = 50,    -- 默认帧间隔 ms，越小动画越快。各任务会再乘自己的速度系数
}

-- ==================== 蛇形走线映射 ====================
-- 本灯板物理走线为蛇形：偶数行从左到右，奇数行从右到左
-- 视觉上的逻辑坐标 (x=列, y=行) 需要通过此函数转换成 ws2812 串中的物理编号
local SERPENTINE = true

--- 逻辑坐标 → 物理 LED 编号
-- @param x 列 0..LED_W-1（从左到右）
-- @param y 行 0..LED_H-1（从上到下）
-- @return 物理 LED 编号 0..LED_COUNT-1
function ws2812_xy(x, y)
    if SERPENTINE and (y % 2 == 1) then
        -- 奇数行走线方向相反，水平翻转
        x = LED_W - 1 - x
    end
    return y * LED_W + x
end

-- ==================== 颜色工具 ====================

--- HSV 颜色空间转 24-bit RGB 整数
-- @param h 色相 0~359（0=红, 120=绿, 240=蓝）
-- @param s 饱和度 0~255（0=灰白, 255=纯色）
-- @param v 明度 0~255（0=黑, 255=最亮）
-- @return 24-bit RGB 整数，可直接传给 ws2812_set / ws2812.fill
function ws2812_hsv2rgb(h, s, v)
    -- 标准 HSV→RGB 算法，参考 https://en.wikipedia.org/wiki/HSL_and_HSV
    local c = v * s / 255 / 255                 -- 色度（chroma）
    local x = c * (1 - math.abs((h / 60) % 2 - 1))  -- 中间色分量
    local m = v / 255 - c                       -- 明度匹配增量
    local r, g, b
    -- 根据色相所在的 60° 扇区决定 RGB 排列
    if h < 60 then       r, g, b = c, x, 0
    elseif h < 120 then  r, g, b = x, c, 0
    elseif h < 180 then  r, g, b = 0, c, x
    elseif h < 240 then  r, g, b = 0, x, c
    elseif h < 300 then  r, g, b = x, 0, c
    else                 r, g, b = c, 0, x
    end
    -- 加上明度增量并打包成 0xRRGGBB
    return math.floor((r + m) * 255 + 0.5) * 65536
         + math.floor((g + m) * 255 + 0.5) * 256
         + math.floor((b + m) * 255 + 0.5)
end

--- 直接用 RGB 三原色打包 24-bit 整数
-- @param r 红 0~255
-- @param g 绿 0~255
-- @param b 蓝 0~255
-- @return 24-bit RGB 整数
function ws2812_rgb(r, g, b)
    return r * 65536 + g * 256 + b
end

-- ==================== WS2812 句柄初始化 ====================
-- ws2812.create(mode, count, pin): 创建 ws2812 句柄
--   mode  = ws2812.GPIO  表示使用普通 GPIO 外设驱动
--   count = LED_COUNT    灯珠总数
--   pin   = LED_GPIO     数据引脚
WS2812_LEDS = ws2812.create(ws2812.GPIO, LED_COUNT, LED_GPIO)
if not WS2812_LEDS then
    log.error("ws2812_config", "ws2812.create 失败，请确认固件含 ws2812 组件")
else
    -- 设置 WS2812 时序（单位 ns），这是本灯板实测稳定的参数：
    --   T0H=20  T0L=30  T1H=35  T1L=20  T_RESET=0 us
    -- 乱改可能导致颜色错乱或整板不亮
    ws2812.args(WS2812_LEDS, 20, 30, 35, 20, 0)

    -- 第一次清屏：创建句柄后立即把缓冲区置 0
    -- 避免上电瞬间 DIN 引脚电气杂波被第一颗 LED 误识别为数据位并锁存（开机鬼影）
    for i = 0, LED_COUNT - 1 do
        ws2812.set(WS2812_LEDS, i, 0)
    end

    -- 后台任务：50ms 后再发送一次真正的复位信号
    -- 此时电源和 DIN 已稳定，能可靠清除所有 LED 的随机锁存
    sys.taskInit(function()
        sys.wait(50)
        for i = 0, LED_COUNT - 1 do
            ws2812.set(WS2812_LEDS, i, 0)
        end
        ws2812.send(WS2812_LEDS)
        log.info("ws2812_config", "LED 已复位清零，共", LED_COUNT, "颗")
    end)
end

-- ==================== 帧缓冲操作函数 ====================
-- ws2812 的工作方式：先把每颗 LED 的颜色写入内部缓冲，再调用 send() 一次性刷新到灯板
-- 下面这组函数都做了 nil 句柄保护，即使 ws2812.create 失败也不会崩溃

--- 按逻辑坐标点亮一颗 LED（写缓冲，不发送）
-- @param x 列 0..LED_W-1
-- @param y 行 0..LED_H-1
-- @param color 24-bit RGB 整数（ws2812_hsv2rgb / ws2812_rgb 的返回值）
function ws2812_set(x, y, color)
    if not WS2812_LEDS then return end
    -- 越界保护：不在灯板范围内的坐标静默忽略
    if x >= 0 and x < LED_W and y >= 0 and y < LED_H then
        ws2812.set(WS2812_LEDS, ws2812_xy(x, y), color)
    end
end

--- 整片填充同一颜色并立即发送
-- @param color 24-bit RGB 整数
function ws2812_fill(color)
    if not WS2812_LEDS then return end
    for i = 0, LED_COUNT - 1 do
        ws2812.set(WS2812_LEDS, i, color)
    end
    ws2812.send(WS2812_LEDS)
end

--- 整片清屏（写缓冲，不发送）
-- 调用后必须再调用 ws2812_send() 才会真正熄灭 LED
function ws2812_clear()
    if not WS2812_LEDS then return end
    for i = 0, LED_COUNT - 1 do
        ws2812.set(WS2812_LEDS, i, 0)
    end
end

--- 发送当前缓冲区到灯板（刷新一帧）
-- 所有 ws2812_set / ws2812_clear 都是写缓冲，必须调用此函数才会生效
function ws2812_send()
    if not WS2812_LEDS then return end
    ws2812.send(WS2812_LEDS)
end
