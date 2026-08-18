--[[
@module  ws2812_rainbow_task
@summary Air1780P/H 演示 WS2812 彩虹渐变效果
@version 1.0
@date    2026.08.17
@usage
适用产品：合宙 Air1780P / Air1780H。
         色相公式依赖 LED_W+LED_H，灯板尺寸非 22×22 时会自动适配，但效果观感可能变化。

本文件为 WS2812 22×22 点阵演示彩虹渐变效果的代码示例，核心业务逻辑为：
1. 遍历 22×22 每一颗灯珠
2. 根据 (x+y) 坐标与当前帧数计算 HSV 色相
3. 刷新整片，形成色彩流动的彩虹效果
]]

-- 定义任务函数
local function rainbow_task()
    -- 防御性检查：若硬件初始化失败或 WS2812_LEDS 未生成，直接退出本任务
    if not WS2812_LEDS then return end
    -- 等待 100ms，让 ws2812_config 完成开机复位与显存清零，避免首帧花屏
    sys.wait(100)
    -- steps：一轮完整色彩循环所需的帧数（120 帧后色相回到起点）
    local steps = 120
    while 1 do
        -- 逐帧推进，frame 作为全局色相偏移量
        for frame = 0, steps - 1 do
            -- 按行扫描每个灯珠
            for y = 0, LED_H - 1 do
                for x = 0, LED_W - 1 do
                    -- 色相 h 由两部分叠加：
                    --   (x+y)*360/(LED_W+LED_H)：空间项，使对角线上同色，形成斜向彩虹条纹
                    --   frame*3：时间项，每帧色相推进 3°，整轮 120 帧正好推进 360°
                    -- 取模 360 保证色相落在 0~359° 区间
                    local h = ((x + y) * 360 / (LED_W + LED_H) + frame * 3) % 360
                    -- 饱和度固定 255（最鲜艳），亮度使用配置值，写入对应坐标
                    ws2812_set(x, y, ws2812_hsv2rgb(h, 255, WS2812_CFG.brightness))
                end
            end
            -- 整帧填充完毕后一次性推送至灯板
            ws2812_send()
            -- 按配置的帧间隔延时，控制动画速度
            sys.wait(WS2812_CFG.speed_ms)
        end
    end
end

-- 执行彩虹任务函数
sys.taskInit(rainbow_task)
