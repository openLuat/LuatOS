--[[
@module  ws2812_scroll_task
@summary Air1780P/H 演示 WS2812 滚动文字效果（欢迎使用LuatOS）
@version 1.0
@date    2026.08.17
@usage
适用产品：合宙 Air1780P / Air1780H。
         字模尺寸为 22 行高，与本灯板 22×22 强绑定；灯板高度非 22 行时需重新生成字模。

本文件为 WS2812 22×22 点阵演示横向滚动文字的代码示例，核心业务逻辑为：
1. 中文 22×22 字模"欢迎使用" + 英文半宽 22×11 字模"LuatOS"
2. 文字从右侧滑入、左侧滑出，循环滚动
3. 每播完一轮自动切换颜色（6 色区随机，且相邻轮次不落在同一色区）
4. 可通过 WS2812_CFG.speed_ms 调速，WS2812_CFG.brightness 调亮度

整体流程：
  系统启动 → 加载字模/配置 → 构建整条文本的"列掩码"缓冲 →
  进入 while 1 循环：每轮 pick_color 选一种与上轮不同色区的颜色 →
  offset 从 -LED_W 走到 strip_w-1，逐帧渲染并等待 speed_ms →
  一轮结束后重新选色再播。
]]

-- ====== 模块依赖与配置兜底 ======

-- 加载字模与条带构建工具（依赖 ws2812_config 已初始化 WS2812_LEDS）
require "ws2812_config"
require "ws2812_fonts"

-- 防止 config 未正确加载时的兜底默认值
-- brightness：亮度（0~255，送入 HSV 的 V 通道）
-- speed_ms：每帧滚动间隔，毫秒；数值越小滚动越快
if not WS2812_CFG then
    WS2812_CFG = { brightness = 50, speed_ms = 80 }
end
if not WS2812_CFG.speed_ms then WS2812_CFG.speed_ms = 80 end
if not WS2812_CFG.brightness then WS2812_CFG.brightness = 50 end

-- ====== 滚动文本 ======

-- 滚动文本（UTF-8 编码）；构建条带时按字节解析，
-- 中文走 3 字节分支、ASCII 走 1 字节分支，详见 ws2812_fonts.lua
local SCROLL_TEXT = "欢迎使用LuatOS"

-- ====== 颜色分区（6 色区互斥） ======

-- 将 HSV 色相环 0~359 切成 6 段，每段 60°，分别对应红/黄/绿/青/蓝/紫。
-- 互斥的目的：相邻两轮如果落在相邻色区（例如红→黄、绿→青），
-- 视觉上颜色变化不明显，观感像"没换色"。
-- 因此 pick_color 用 repeat...until 强制抽到与 prev_zone 不同的区，
-- 保证每一轮的颜色都与上一轮有显著色差。
local COLOR_ZONES = {
    {  0,  59},  -- 红
    { 60, 119},  -- 黄
    {120, 179},  -- 绿
    {180, 239},  -- 青
    {240, 299},  -- 蓝
    {300, 359},  -- 紫
}

-- ====== LCG 伪随机数发生器 ======

-- 采用 glibc 风格的线性同余发生器（LCG, Linear Congruential Generator）：
--   seed = (seed * 1103515245 + 12345) mod 2^31
-- 这是 C 语言 rand() 的经典公式，分布足够均匀，且不依赖 Lua 的 math.random
-- （嵌入式固件中 math.random 可能未播种或不可用）。
-- 种子取 os.time() 对 2^31-1 取模，保证每次上电随机序列不同。
local lcg_seed = os.time() % 2147483647

--- 产出下一个 0~32767 范围的伪随机整数
-- @return integer 伪随机数（0~32767）
local function lcg_next()
    -- 递推：固定乘数 1103515245、增量 12345、模数 2^31
    lcg_seed = (lcg_seed * 1103515245 + 12345) % 2147483648
    -- 取高 15 位（除以 65536 后再 mod 32768），低位随机性较差故舍弃
    return math.floor(lcg_seed / 65536) % 32768
end

-- 记录上一轮使用的色区索引，初值 -1 保证第一轮必能抽到任意色区
local prev_zone = -1

--- 从与上一轮不同的色区中随机选一种颜色
-- @return table {r,g,b}，经 ws2812_hsv2rgb 转换后的 RGB 三元组
local function pick_color()
    local idx
    -- repeat...until：反复抽色区，直到抽到的索引与 prev_zone 不同，
    -- 从而避免相邻两轮落在同色区导致视觉颜色相近。
    repeat
        idx = lcg_next() % #COLOR_ZONES
    until idx ~= prev_zone
    prev_zone = idx

    -- 从选中的色区中再随机取一个具体色相 h，S=255（最饱和），V=亮度配置
    local z = COLOR_ZONES[idx + 1]
    local h = z[1] + lcg_next() % (z[2] - z[1] + 1)
    return ws2812_hsv2rgb(h, 255, WS2812_CFG.brightness)
end

-- ====== 单帧渲染 ======

--- 将整条文本条带按当前 offset 渲染到 WS2812 并发送
-- columns 是"列掩码"数组：每一个元素是一个 22-bit 整数，
-- 第 y 位为 1 表示该列第 y 行的 LED 需要点亮。
-- 这样一整行只需一次按位与即可判断是否亮灯，渲染效率高。
-- @param columns table  由 ws2812_build_strip 构建的列位数组
-- @param offset  integer 文本相对屏幕左边缘的水平偏移（负数表示文本还在屏幕右侧外）
-- @param color   table   {r,g,b} 当前轮次统一使用的颜色
local function render_frame(columns, offset, color)
    ws2812_clear()
    -- 从上到下遍历 22 行
    for y = 0, WS2812_STRIP_H - 1 do
        -- bit = 1<<y：构造当前行的位掩码。
        -- 列掩码第 y 位为 1 时，(columns[c] & bit) ~= 0 即表示该位置亮。
        local bit = 1 << y
        -- 从左到右遍历屏幕的 LED_W 列
        for x = 0, LED_W - 1 do
            -- col_idx = x + offset + 1
            --   x       ：屏幕列号（0 起始）
            --   offset  ：文本滚动偏移
            --   +1      ：Lua 数组从 1 起始，columns[1] 对应文本第 1 列
            -- 含义：屏幕第 x 列当前对应文本的第 (x+offset) 列。
            local col_idx = x + offset + 1  -- Lua 数组 1 起始
            -- 双向越界保护：offset 为负或文本已滚出左侧时，col_idx 会落在数组外
            if col_idx >= 1 and col_idx <= #columns then
                if (columns[col_idx] & bit) ~= 0 then
                    ws2812_set(x, y, color)
                end
            end
        end
    end
    ws2812_send()
end

-- ====== 滚动任务主循环 ======

--- 滚动文字任务函数（由 sys.taskInit 启动为协程）
local function scroll_task()
    -- WS2812_LEDS 未初始化说明硬件未就绪，直接退出避免空指针
    if not WS2812_LEDS then return end

    -- 等待 config 的开机复位清零（50ms）完成，避免首帧与复位冲突
    sys.wait(100)

    -- 一次性把整段文本展开成列掩码数组（包含字间距空白列），
    -- strip_w 即整条文本的总列数，后面滚动范围由它决定
    local columns = ws2812_build_strip(SCROLL_TEXT)
    local strip_w = #columns
    log.info("scroll", "文本:", SCROLL_TEXT, "条带宽度:", strip_w)

    while 1 do
        -- 每轮重新 pick_color：一轮完整滚动结束后换一种颜色再播，
        -- 让画面有"翻篇"感；repeat...until 已保证与上轮色区不同
        local color = pick_color()

        -- 滚动循环：
        --   offset = -LED_W    起始：文本整体在屏幕右侧之外，屏幕全黑（右侧滑入前一刻）
        --   offset = -LED_W+1  开始：文本第一列从屏幕最右列 (x=LED_W-1) 出现
        --   offset = 0         文本首列正好对齐屏幕首列
        --   offset = strip_w-1 终值：文本最后一列刚划过屏幕第 0 列（左侧滑出完成）
        -- 循环结束即整条文本完全离开屏幕，随后 while 1 重新选色再开一轮。
        for offset = -LED_W, strip_w - 1 do
            render_frame(columns, offset, color)
            -- 每帧之间等待 speed_ms 毫秒，让出 CPU 给其他协程，
            -- 同时控制滚动速度：值越小滚动越快、越流畅；值越大越慢、越卡顿
            sys.wait(WS2812_CFG.speed_ms)
        end
    end
end

-- ====== 任务启动 ======

-- 执行滚动文字任务函数：sys.taskInit 将其作为 LuatOS 协程调度，
-- 内部 sys.wait 不会阻塞系统其他任务
sys.taskInit(scroll_task)
