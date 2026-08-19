--[[
@module  ws2812_rect_task
@summary Air1780P/H/HV 演示 WS2812 矩形收缩扩散效果
@version 1.0
@date    2026.08.17
@usage
适用产品：合宙 Air1780P / Air1780H / Air1780HV。
         中心点 (11,11) 按 22×22 几何中心计算，灯板尺寸非 22×22 时需同步修改。

本文件为 WS2812 22×22 点阵演示矩形收缩扩散效果的代码示例，核心业务逻辑为：
1. 从中心点开始画矩形框
2. 矩形半径由小到大、再由大到小，形成呼吸般的扩散/收缩
3. 颜色随半径变化
]]

-- 定义任务函数
local function rect_task()
    -- 防御性检查：硬件未就绪直接退出，避免后续访问空显存
    if not WS2812_LEDS then return end
    -- 等待 100ms，让 config 完成开机复位清零，防止首帧花屏
    sys.wait(100)
    -- max_r：矩形最大"半径"（半边长），取宽高较小值的一半，保证矩形不超出点阵
    -- math.floor 取整是为了让 r 的 numeric for 走整数步长，避免浮点累计误差
    local max_r = math.floor(math.min(LED_W, LED_H) / 2)
    while 1 do
        -- 两阶段动画：
        --   phase = 0：扩散（半径 0 → max_r）
        --   phase = 1：收缩（半径 max_r → 0），通过 rr 反向映射实现
        for phase = 0, 1 do
            -- r 作为统一推进变量，始终从 0 增长到 max_r
            for r = 0, max_r do
                -- 每帧清屏，只保留当前半径对应的矩形框
                ws2812_clear()
                -- 实际渲染半径：扩散阶段用 r，收缩阶段用 max_r - r，从而形成呼吸节奏
                local rr = (phase == 0) and r or (max_r - r)
                -- 中心点 (11,11)：22×22 点阵的几何中心（22/2 = 11）
                local cx = math.floor(LED_W / 2)
                local cy = math.floor(LED_H / 2)
                -- 矩形四条边的边界坐标：
                --   x0/y0：左上，x1/y1：右下；-1 是因为 rr 表示"半边长"，
                --   边长为 2*rr 时右/下边界需要减 1，避免单边多出一列/一行
                local x0 = cx - rr
                local x1 = cx + rr - 1
                local y0 = cy - rr
                local y1 = cy + rr - 1
                -- 色相随半径变化：半径每增加 1，色相推进 20°，取模 360 实现循环变色
                local h = (rr * 20) % 360
                -- 预计算当前帧颜色，四条边复用同一个颜色值
                local c = ws2812_hsv2rgb(h, 255, WS2812_CFG.brightness)
                -- 绘制上下两条水平边：每个 x 坐标在 y0 和 y1 上各点亮一颗
                for x = x0, x1 do
                    ws2812_set(x, y0, c)
                    ws2812_set(x, y1, c)
                end
                -- 绘制左右两条垂直边：每个 y 坐标在 x0 和 x1 上各点亮一颗
                -- 四个角点会被重复 set，但同色写入无副作用
                for y = y0, y1 do
                    ws2812_set(x0, y, c)
                    ws2812_set(x1, y, c)
                end
                -- 整帧刷新
                ws2812_send()
                -- 速度系数 *3：矩形呼吸需要沉稳节奏，比基础帧间隔慢两倍，视觉更柔和
                sys.wait(WS2812_CFG.speed_ms * 3)
            end
        end
    end
end

-- 执行矩形任务函数
sys.taskInit(rect_task)
