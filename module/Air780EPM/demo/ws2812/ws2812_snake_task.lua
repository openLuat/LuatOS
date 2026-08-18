--[[
@module  ws2812_snake_task
@summary Air1780P/H 演示 WS2812 蛇形扫描效果
@version 1.0
@date    2026.08.17
@usage
适用产品：合宙 Air1780P / Air1780H。
         本任务按物理 LED 编号顺序扫描，灯板尺寸非 22×22 时请确认蛇形走线方向与本灯板一致。

本文件为 WS2812 22×22 点阵演示蛇形扫描效果的代码示例，核心业务逻辑为：
1. 一颗带拖尾的光点按物理 LED 编号顺序跑动
2. 由于灯板蛇形走线，视觉上呈"S 形"逐行扫描
3. 拖尾 6 颗，颜色随位置渐变
]]

-- 定义任务函数
local function snake_task()
    -- 防御性检查：WS2812_LEDS 不存在说明硬件未就绪，直接退出避免后续 ws2812.set 报错
    if not WS2812_LEDS then return end
    -- 等待 100ms，让 config 完成开机复位和显存清零
    sys.wait(100)
    -- trail：光点拖尾长度（含光点本身共 7 个位置，t 从 0 到 6）
    local trail = 6
    while 1 do
        -- i 是光点当前"虚拟头位置"，多跑 trail 个位置，让光点完全滑出后再循环，收尾更自然
        for i = 0, LED_COUNT + trail do
            -- 每帧先清空，再重绘拖尾，避免残影叠加
            ws2812_clear()
            -- 依次绘制拖尾上的每一颗：t=0 是头部（最亮），t=trail 是尾部（最暗）
            for t = 0, trail do
                -- idx = i - t：头部位置往回倒 t 个索引，得到第 t 节拖尾的物理 LED 编号
                local idx = i - t
                -- 越界保护：光点进入/滑出边界时，拖尾可能落在 0~LED_COUNT-1 之外
                if idx >= 0 and idx < LED_COUNT then
                    -- fade：线性渐暗系数，t=0 时为 1（全亮），t=trail 时为 0（熄灭）
                    local fade = (trail - t) / trail
                    -- 根据渐暗系数缩放配置亮度，得到该节拖尾的实际明度
                    local v = math.floor(WS2812_CFG.brightness * fade)
                    -- 色相按物理 LED 编号均匀分布在 0~360°，让蛇身呈现彩虹渐变
                    local h = (idx * 360 / LED_COUNT) % 360
                    -- 直接调用底层 ws2812.set 写入物理索引（本效果按编号顺序而非坐标）
                    ws2812.set(WS2812_LEDS, idx, ws2812_hsv2rgb(h, 255, v))
                end
            end
            -- 整帧刷新
            ws2812_send()
            -- 速度系数 *2：蛇形需要明显的移动节奏感，比基础帧间隔放慢一倍更耐看
            sys.wait(WS2812_CFG.speed_ms * 2)
        end
    end
end

-- 执行蛇形扫描任务函数
sys.taskInit(snake_task)
