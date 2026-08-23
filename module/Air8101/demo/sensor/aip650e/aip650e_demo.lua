--[[
@module  aip650e_demo
@summary AiP650E 驱动芯片演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.13
@author  江访
@usage
本文件包含 AiP650E 的逐项功能演示和综合展示。
通过 exs_aip650e 扩展库的 API 逐一演示数码管显示、按键检测、亮度调节、
7段/8段模式切换、睡眠唤醒等功能。
]]

-- 加载 exs_aip650e 扩展库
local exs_aip650e = require "exs_aip650e"

-- 演示字符串显示
local function demo_string()
    log.info("aip650e_demo", "===== [1/6] 字符串显示 =====")

    log.info("aip650e_demo", "显示 1234")
    exs_aip650e.clear()
    exs_aip650e.set_display("1234")
    sys.wait(1500)

    log.info("aip650e_demo", "显示 88.8")
    exs_aip650e.clear()
    exs_aip650e.set_display("88.8")
    sys.wait(1500)

    log.info("aip650e_demo", "显示 AbCd")
    exs_aip650e.clear()
    exs_aip650e.set_display("AbCd")
    sys.wait(1500)

    log.info("aip650e_demo", "从第 3 位开始显示 12")
    exs_aip650e.clear()
    exs_aip650e.set_display("12", 3)
    sys.wait(1500)

    log.info("aip650e_demo", "显示 HELO")
    exs_aip650e.clear()
    exs_aip650e.set_display("HELO")
    sys.wait(1500)

    exs_aip650e.clear()
    sys.wait(500)
end

-- 演示按键轮询
local function demo_keys()
    log.info("aip650e_demo", "===== [2/6] 按键轮询 =====")
    log.info("aip650e_demo", "请在 10 秒内按下连接到 AiP650E 的按键...")

    exs_aip650e.clear()
    exs_aip650e.set_display("KEYS")

    local timeout = 10000
    local step = 100
    local elapsed = 0

    while elapsed < timeout do
        local key = exs_aip650e.get_key()
        if key then
            log.info("aip650e_demo", "检测到按键, 编码:", key)
            local key_str = string.format("%02d", key)
            exs_aip650e.set_display(key_str)
            sys.wait(1000)
            return
        end
        sys.wait(step)
        elapsed = elapsed + step
    end

    log.info("aip650e_demo", "按键检测超时，跳过")
end

-- 按键回调函数
local function on_key(key_code)
    log.info("aip650e_demo", "按键回调触发, 编码:", key_code)
    local display = string.format("%02d", key_code)
    exs_aip650e.set_display(display)
end

-- 演示按键回调
local function demo_key_callback()
    log.info("aip650e_demo", "===== [3/6] 按键回调 =====")
    log.info("aip650e_demo", "接下来 15 秒内按按键查看回调效果")

    exs_aip650e.clear()
    exs_aip650e.set_display("CALL")
    exs_aip650e.set_key_callback(on_key)

    sys.wait(15000)

    exs_aip650e.set_key_callback(nil)
    log.info("aip650e_demo", "按键回调演示结束")
end

-- 演示亮度调节
local function demo_brightness()
    log.info("aip650e_demo", "===== [4/6] 亮度调节 =====")

    exs_aip650e.clear()
    exs_aip650e.set_display("8888")
    sys.wait(500)

    for bright = 0, 7 do
        log.info("aip650e_demo", "设置亮度:", bright)
        exs_aip650e.set_brightness(bright)
        sys.wait(800)
    end

    -- 恢复默认亮度
    exs_aip650e.set_brightness(4)
    exs_aip650e.clear()
    sys.wait(500)
end

-- 演示 7段/8段 模式切换
local function demo_segment_mode()
    log.info("aip650e_demo", "===== [5/6] 7段/8段模式切换 =====")

    -- 8 段模式（含 DP 段），显示数字
    exs_aip650e.clear()
    exs_aip650e.set_mode(0)
    exs_aip650e.set_display("8SEG")
    sys.wait(2000)

    -- 显示带小数点的内容（8 段模式特性）
    exs_aip650e.clear()
    exs_aip650e.set_display("88.8")
    sys.wait(2000)

    -- 切换到 7 段模式
    exs_aip650e.clear()
    exs_aip650e.set_mode(1)
    exs_aip650e.set_display("7SEG")
    sys.wait(2000)

    exs_aip650e.clear()
    sys.wait(500)

    -- 切回 8 段模式
    exs_aip650e.set_mode(0)
end

-- 综合演示
local function demo_final()
    log.info("aip650e_demo", "===== [6/6] 综合演示 =====")

    -- 倒计时
    for i = 5, 0, -1 do
        exs_aip650e.clear()
        exs_aip650e.set_display(string.format("%04d", i))
        sys.wait(500)
    end

    -- HELLO 闪烁
    for i = 0, 3 do
        exs_aip650e.clear()
        exs_aip650e.set_display("HELO")
        sys.wait(500)
        exs_aip650e.clear()
        sys.wait(300)
    end

    -- 全 8 显示 + 亮度渐变
    exs_aip650e.clear()
    exs_aip650e.set_display("8888")
    for i = 0, 7 do
        exs_aip650e.set_brightness(i)
        sys.wait(200)
    end
    sys.wait(1000)
    exs_aip650e.set_brightness(4)
    exs_aip650e.clear()

    -- 日期展示
    log.info("aip650e_demo", "日期展示: 26-07-13")
    exs_aip650e.set_display("26-07-13")
    sys.wait(3000)

    -- 温度展示（摄氏度）
    exs_aip650e.clear()
    sys.wait(200)
    local DEGREE = "\xB0"
    for temp = 25, 32 do
        local cel = string.format("%02d", temp) .. DEGREE .. "C"
        exs_aip650e.set_display(cel)
        local bright = math.floor((temp - 25) / 7 * 7 + 0.5)
        if bright < 0 then bright = 0 end
        if bright > 7 then bright = 7 end
        exs_aip650e.set_brightness(bright)
        sys.wait(800)
    end

    -- 温度展示（华氏度）
    for temp = 77, 90, 2 do
        local fah = string.format("%02d", temp) .. DEGREE .. "F"
        exs_aip650e.set_display(fah)
        sys.wait(600)
    end

    exs_aip650e.set_brightness(5)
    sys.wait(2000)
    exs_aip650e.clear()

    -- 演示开启/关闭显示
    log.info("aip650e_demo", "显示关闭演示")
    exs_aip650e.set_display("OFF_")
    sys.wait(2000)
    exs_aip650e.display_off()
    sys.wait(2000)
    exs_aip650e.display_on()
    sys.wait(2000)
    exs_aip650e.clear()

    log.info("aip650e_demo", "---- 综合演示结束 ----")
end

-- 演示主函数（运行在协程中）
local function aip650e_demo_task_func()
    -- 初始化 (Air8101: CLK=4, DIO=5)
    local result = exs_aip650e.setup({
        clk        = 4,
        dio        = 5,
        bright     = 5,
    })
    if not result then
        log.error("aip650e_demo", "AiP650E 初始化失败，请检查接线")
        return
    end

    log.info("aip650e_demo", "AiP650E 初始化成功，版本:", exs_aip650e.version())

    -- HELLO 开始 → [1/6] → [2/6] → [3/6] → [4/6] → [5/6] → [6/6] → End
    exs_aip650e.set_display("HELO")
    sys.wait(1000)

    demo_string()
    demo_keys()
    demo_key_callback()
    demo_brightness()
    demo_segment_mode()
    demo_final()

    exs_aip650e.set_display("End-")
    sys.wait(3000)
    log.info("aip650e_demo", "===== [演示完毕] =====")
end

sys.taskInit(aip650e_demo_task_func)
