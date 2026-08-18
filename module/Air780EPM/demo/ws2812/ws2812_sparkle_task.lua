--[[
@module  ws2812_sparkle_task
@summary Air1780P/H 演示 WS2812 随机星点闪烁效果
@version 1.0
@date    2026.08.17
@usage
适用产品：合宙 Air1780P / Air1780H。
         星点数量和色相范围通过 LED_W/LED_H 计算，灯板尺寸非 22×22 时会自动适配。

本文件为 WS2812 22×22 点阵演示随机星点闪烁效果的代码示例，核心业务逻辑为：
1. 每帧随机点亮 30 颗灯珠
2. 每颗灯珠使用随机色相
3. 形成类似星空闪烁的视觉效果
]]

-- 定义任务函数
local function sparkle_task()
    -- 防御性检查：显存未初始化则直接返回，防止后续写显存时空引用
    if not WS2812_LEDS then return end
    -- 等待 100ms，让 config 完成开机复位清零，避免首帧残留
    sys.wait(100)
    while 1 do
        -- 外层循环：一轮包含 100 帧，随后重新开始（数学上无差别，仅用于划分"一轮"）
        for _ = 1, 100 do
            -- 每帧先清空整片，让上一帧星点全部熄灭，形成"闪烁"而非"叠加"
            ws2812_clear()
            -- 每帧随机点亮 30 颗灯珠（约占 484 颗总数的 6%，稀疏度适中）
            for _ = 1, 30 do
                -- x 随机范围 [0, LED_W-1]，即 0~21
                local x = math.random(0, LED_W - 1)
                -- y 随机范围 [0, LED_H-1]，即 0~21
                local y = math.random(0, LED_H - 1)
                -- 色相 h 随机范围 [0, 359]，HSV 全色域取色
                local h = math.random(0, 359)
                -- 写入该坐标；多次命中同一坐标时后者覆盖前者，符合随机闪烁观感
                ws2812_set(x, y, ws2812_hsv2rgb(h, 255, WS2812_CFG.brightness))
            end
            -- 刷新显示
            ws2812_send()
            -- 帧间隔在基础速度上放慢一倍，让星点切换不至于过快刺眼
            sys.wait(WS2812_CFG.speed_ms * 2)
        end
    end
end

-- 执行星点闪烁任务函数
sys.taskInit(sparkle_task)
