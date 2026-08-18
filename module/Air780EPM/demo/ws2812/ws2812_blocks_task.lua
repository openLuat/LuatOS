--[[
@module  ws2812_blocks_task
@summary Air1780P/H 演示 WS2812 色块覆盖 / LED 灯珠检测
@version 1.1
@date    2026.08.17
@usage
适用产品：合宙 Air1780P / Air1780H。
         本任务直接对 WS2812 物理编号 0..LED_COUNT-1 操作，灯板尺寸不是 22×22 时请修改 LED_COUNT。

本文件用于开机色块整板覆盖演示，同时可作为 LED 灯珠检测 demo，
方便客户逐色检查每颗 WS2812 是否存在坏点、虚焊、颜色通道缺失。

检测流程（循环执行）：
1. 逐颗覆盖（红）：按物理蛇形顺序从 0 到 483 逐颗点亮，验证走线顺序与焊接
2. 全红停留 2 秒：检查红色通道
3. 全绿停留 2 秒：检查绿色通道
4. 全蓝停留 2 秒：检查蓝色通道
5. 全白停留 2 秒：检查三通道同时点亮（最耗电，注意供电）
6. 清屏 1 秒后回到步骤 1 切换下一种颜色重新覆盖

若只需要开机过渡效果（跑 2 圈后退出），把 DETECT_LOOP 改为 false。

依赖：ws2812_config.lua 中需提供 LED_COUNT / WS2812_LEDS / ws2812_send /
      ws2812_clear / ws2812_hsv2rgb / ws2812_rgb 等全局量。
]]

require "ws2812_config"

-- 配置缺省值兜底：外部未传 WS2812_CFG 时给一组安全默认值
if not WS2812_CFG then WS2812_CFG = { brightness = 50, speed_ms = 50 } end
if not WS2812_CFG.brightness then WS2812_CFG.brightness = 50 end

-- ====== 配置参数 ======

-- DETECT_LOOP 两种工作模式：
--   true  = 灯珠检测模式：无限循环“逐颗覆盖 + 红绿蓝白纯色全屏”，供产线/客户验灯；
--   false = 开机过渡模式：只跑 BLOCK_ROUNDS 圈随机色覆盖后清屏退出，不做纯色检测。
local DETECT_LOOP = true
-- 非循环模式下跑几圈
local BLOCK_ROUNDS = 2
-- 每推进一颗灯的间隔 ms（覆盖阶段）
local FILL_STEP_MS = 10
-- 每填满一轮后停顿 ms
local HOLD_MS = 300
-- 纯色检测停留时间 ms（红/绿/蓝/白各停多久）
local DETECT_HOLD_MS = 2000
-- 轮次之间清屏停留 ms
local GAP_MS = 1000

-- 检测阶段使用的纯色序列（顺序：红→绿→蓝→白）
-- 每通道 255 为“满量程原色”，实际显示时会再按 brightness 缩放
local DETECT_COLORS = {
    { r = 255, g =   0, b =   0, name = "RED"   },
    { r =   0, g = 255, b =   0, name = "GREEN" },
    { r =   0, g =   0, b = 255, name = "BLUE"  },
    { r = 255, g = 255, b = 255, name = "WHITE" },
}

-- 6 个互斥色区（覆盖阶段随机选色，保证相邻轮次颜色明显不同）
-- 每个区间是 HSV 色相 H 的 [起, 止] 范围（0~359 度），分别对应红/黄/绿/青/蓝/紫
local COLOR_ZONES = {
    {  0,  59},  -- 红
    { 60, 119},  -- 黄
    {120, 179},  -- 绿
    {180, 239},  -- 青
    {240, 299},  -- 蓝
    {300, 359},  -- 紫
}

-- ====== 随机颜色（自带 LCG，不依赖 math.random） ======
-- 这里没有直接用 math.random，原因：
--   1) 嵌入式 LuatOS 固件中 math.random 的可用性/种子行为不稳定，
--      未显式 seed 时多次开机可能拿到相同序列；
--   2) 色块演示只需要“看起来随机且每次不同”，用 glibc 经典 LCG
--      （Linear Congruential Generator，线性同余发生器）即可，
--      纯整数运算、无浮点、无外部依赖、可预测且足够轻量。
-- 常量来源：glibc rand()，公式  seed' = (seed * 1103515245 + 12345) mod 2^31
--   1103515245 与 12345 是 glibc 选定的乘数/增量，周期约 2^31；
--   2147483647 = 2^31 - 1，用于把 os.time() 截到 31 位有符号正数范围作种子；
--   2147483648 = 2^31，是 LCG 状态的模值（结果落在 [0, 2^31-1]）。
local lcg_seed = os.time() % 2147483647

--- 返回下一个 0~32767 的伪随机整数
-- @return integer 伪随机值，范围 [0, 32767]
-- 取高 15 位：先 /65536 右移 16 位，再 %32768 保留 15 位（glibc rand 习惯）
local function lcg_next()
    lcg_seed = (lcg_seed * 1103515245 + 12345) % 2147483648
    return math.floor(lcg_seed / 65536) % 32768
end

-- 记录上一次选中的色区，初始 -1 保证第一次一定能选到任意色区
local prev_zone = -1

--- 从 6 个色区中挑一个（与上轮不同），再在该区内随机取一个色相，
--- 转成受 brightness 约束的 RGB 颜色。
-- @return integer ws2812 可用的颜色值（已按全局亮度缩放 V 分量）
local function pick_color()
    local idx
    repeat
        -- % #COLOR_ZONES 把随机数映射到 [1,6] 的数组下标减一（Lua 数组从 1 开始）
        idx = lcg_next() % #COLOR_ZONES
    until idx ~= prev_zone
    prev_zone = idx
    local z = COLOR_ZONES[idx + 1]
    -- 在色区 [z[1], z[2]] 内均匀取一个色相值 H
    local h = z[1] + lcg_next() % (z[2] - z[1] + 1)
    -- S=255 高饱和；V=brightness 直接受全局亮度钳位，避免覆盖阶段过亮
    return ws2812_hsv2rgb(h, 255, WS2812_CFG.brightness)
end

-- ====== 填充函数 ======

--- 把整板所有灯珠填成同一颜色并发送
-- @param color integer ws2812 颜色值
-- @return 无
local function fill_all(color)
    for i = 0, LED_COUNT - 1 do
        ws2812.set(WS2812_LEDS, i, color)
    end
    ws2812_send()
end

--- 按蛇形物理顺序逐颗点亮整板（已点亮的保持 color 不熄灭）
-- @param color integer ws2812 颜色值
-- @return 无
-- 批量发送策略：每推进 8 颗或到达最后一颗时才调用一次 send。
--   head % 8 == 0 即“每行 8 颗对齐”，既保证动画有连贯的流动感，
--   又避免每点亮一颗就关中断发送一次（WS2812 发送期间 CPU 被占用，
--   发得太密会拖慢系统、心跳/其他任务卡顿）。
local function sequential_cover(color)
    for head = 0, LED_COUNT - 1 do
        ws2812.set(WS2812_LEDS, head, color)
        if (head % 8 == 0) or (head == LED_COUNT - 1) then
            ws2812_send()
        end
        sys.wait(FILL_STEP_MS)
    end
    -- 兜底再发一次，确保最后一批 set 的数据真正送到灯带
    ws2812_send()
end

-- ====== 任务主函数 ======

--- 色块覆盖 / 灯珠检测任务主体
-- 根据 DETECT_LOOP 选择无限循环验灯或开机过渡 N 圈后退出。
-- @return 无
local function blocks_task()
    if not WS2812_LEDS then return end
    sys.wait(100)  -- 等待 config 开机复位清零完成

    if DETECT_LOOP then
        -- ==================== 灯珠检测模式（无限循环） ====================
        log.info("blocks", "LED 灯珠检测模式启动，共", LED_COUNT, "颗灯珠")
        while true do
            -- 阶段 1：逐颗覆盖（用随机彩色，方便观察蛇形走线是否正确）
            sequential_cover(pick_color())
            sys.wait(HOLD_MS)

            -- 阶段 2：红/绿/蓝/白 纯色全屏，每色停留 2 秒
            for _, c in ipairs(DETECT_COLORS) do
                -- 纯色必须按 brightness 缩放：
                --   483 颗 WS2812 三通道满亮时峰值电流可达数安甚至近 30A，
                --   远超 USB/常规供电能力，会导致压降、复位、颜色失真；
                --   按亮度比例缩放 R/G/B 可把整板功率压在供电安全范围内，
                --   同时仍能完整检验每个颜色通道是否正常。
                local b = WS2812_CFG.brightness
                local color = ws2812_rgb(
                    math.floor(c.r * b / 255),
                    math.floor(c.g * b / 255),
                    math.floor(c.b * b / 255)
                )
                fill_all(color)
                log.info("blocks", "检测颜色:", c.name, "亮度:", b)
                sys.wait(DETECT_HOLD_MS)
            end

            -- 清屏停顿
            ws2812_clear()
            ws2812_send()
            sys.wait(GAP_MS)
        end
    else
        -- ==================== 开机过渡模式（跑 N 圈后退出） ====================
        for round = 1, BLOCK_ROUNDS do
            local color = pick_color()
            log.info("blocks", "第", round, "圈开始")
            sequential_cover(color)
            log.info("blocks", "第", round, "圈完成")
            sys.wait(HOLD_MS)
        end
        ws2812_clear()
        ws2812_send()
        log.info("blocks", "色块覆盖结束")
    end
end

-- 执行色块覆盖任务函数
sys.taskInit(blocks_task)
