--[[
@module  tm1638_demo
@summary TM1638 驱动芯片演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.07
@author  江访
@usage
本文件包含 TM1638 的逐项功能演示和综合展示。
通过 exs_tm1638 扩展库的 API 逐一演示数码管显示、LED 控制、按键检测等功能。
]]

-- 加载 exs_tm1638 扩展库
local exs_tm1638 = require "exs_tm1638"

-- 演示字符串显示
local function demo_string()
    log.info("tm1638_demo", "===== [1/7] 字符串显示 =====")

    log.info("tm1638_demo", "显示 87654321")
    exs_tm1638.clear()
    exs_tm1638.set_display("87654321")
    sys.wait(1500)

    log.info("tm1638_demo", "显示 88.88")
    exs_tm1638.clear()
    exs_tm1638.set_display("88.88")
    sys.wait(1500)

    log.info("tm1638_demo", "显示 AbCd")
    exs_tm1638.clear()
    exs_tm1638.set_display("AbCd")
    sys.wait(1500)

    log.info("tm1638_demo", "从第 3 位开始显示 1234")
    exs_tm1638.clear()
    exs_tm1638.set_display("1234", 3)
    sys.wait(1500)

    exs_tm1638.clear()
    sys.wait(500)
end

-- 演示 LED 指示灯
local function demo_leds()
    log.info("tm1638_demo", "===== [2/7] LED =====")

    for i = 1, 8 do
        exs_tm1638.set_display(string.format("%d", i))
        exs_tm1638.set_led(true, i)
        sys.wait(300)
    end

    sys.wait(1000)

    log.info("tm1638_demo", "逐个熄灭")
    for i = 1, 8 do
        exs_tm1638.set_led(false, i)
        sys.wait(200)
    end

    log.info("tm1638_demo", "LED 跑马灯")
    exs_tm1638.clear()
    for round = 1, 3 do
        for i = 1, 8 do
            if i > 1 then
                exs_tm1638.set_led(false, i - 1)
            else
                exs_tm1638.set_led(false, 8)
            end
            exs_tm1638.set_led(true, i)
            exs_tm1638.set_display(string.format("%d", i))
            sys.wait(150)
        end
    end

    exs_tm1638.clear()
    sys.wait(500)
end

-- 演示按键轮询
local function demo_keys()
    log.info("tm1638_demo", "===== [3/7] 按键轮询 =====")
    log.info("tm1638_demo", "请在 10 秒内按下连接到 TM1638 的按键...")

    exs_tm1638.clear()
    exs_tm1638.set_display("KEY----")

    local timeout = 10000
    local step = 100
    local elapsed = 0

    while elapsed < timeout do
        local key = exs_tm1638.get_key()
        if key then
            exs_tm1638.clear()
            log.info("tm1638_demo", "检测到按键, 编码:", key)
            local key_str = string.format("K%02d", key)
            exs_tm1638.set_display(key_str)
            sys.wait(1000)
            return
        end
        sys.wait(step)
        elapsed = elapsed + step
    end

    log.info("tm1638_demo", "按键检测超时，跳过")
end

-- 演示亮度调节
local function demo_brightness()
    log.info("tm1638_demo", "===== [4/7] 亮度调节 =====")

    exs_tm1638.clear()
    exs_tm1638.set_display("88888888")
    sys.wait(500)

    for brightness = 0, 7 do
        log.info("tm1638_demo", "设置亮度:", brightness)
        exs_tm1638.set_brightness(brightness)
        sys.wait(800)
    end

    exs_tm1638.set_brightness(4)
    exs_tm1638.clear()
    sys.wait(500)
end

-- 按键回调函数
local function on_key(key_code)
    log.info("tm1638_demo", "按键回调触发, 编码:", key_code)
    local display = string.format("K%02d", key_code)
    exs_tm1638.set_display(display)
end

-- 演示按键回调
local function demo_key_callback()
    log.info("tm1638_demo", "[5/7] 按键回调（15 秒内按按键演示）")

    exs_tm1638.clear()
    exs_tm1638.set_display("Cb-Key")
    exs_tm1638.set_key_callback(on_key)

    sys.wait(15000)

    exs_tm1638.set_key_callback(nil)
    log.info("tm1638_demo", "按键回调演示结束")
end

-- 综合演示
local function demo_final_show()
    log.info("tm1638_demo", "===== [6/7] 综合演示 =====")

    for i = 5, 0, -1 do
        exs_tm1638.clear()
        exs_tm1638.set_display(string.format("%d", i))
        for j = 1, 8 do
            exs_tm1638.set_led(false, j)
        end
        sys.wait(500)
    end

    for i = 0, 3 do
        exs_tm1638.clear()
        exs_tm1638.set_display("-HELLO-")
        sys.wait(500)
        exs_tm1638.clear()
        sys.wait(300)
    end

    exs_tm1638.clear()
    exs_tm1638.set_display("88888888")
    for i = 1, 8 do
        exs_tm1638.set_led(true, i)
    end

    for i = 0, 7 do
        exs_tm1638.set_brightness(i)
        sys.wait(200)
    end

    sys.wait(1000)
    exs_tm1638.clear()

    for i = 1, 8 do
        exs_tm1638.set_led(false, i)
    end

    log.info("tm1638_demo", "---- 综合演示结束 ----")
end

-- 展示日期：格式 "26-07-08"
local function show_date()
    log.info("tm1638_demo", "日期展示: 26-07-08")
    exs_tm1638.set_display("26-07-08")
    sys.wait(3000)
    exs_tm1638.clear()
end

-- 展示时间：模拟走时 "08-30-00" ~ "08-30-09"
local function show_clock()
    exs_tm1638.clear()
    sys.wait(200)
    log.info("tm1638_demo", "时钟展示: 08-30-00 ~ 08-30-09")
    for sec = 0, 9 do
        exs_tm1638.set_display(string.format("08-30-%02d", sec))
        sys.wait(500)
    end
end

-- 展示温度：摄氏度用 "°C"，华氏度用 "°F"
local function show_temperature()
    exs_tm1638.clear()
    sys.wait(200)
    local DEGREE = "°"
    for temp = 25, 32 do
        local cel = string.format("%02d", temp) .. DEGREE .. "C"
        exs_tm1638.set_display(cel)
        local bright = math.floor((temp - 25) / 7 * 7 + 0.5)
        if bright < 0 then bright = 0 end
        if bright > 7 then bright = 7 end
        exs_tm1638.set_brightness(bright)
        sys.wait(800)
    end

    for temp = 77, 90, 2 do
        local fah = string.format("%02d", temp) .. DEGREE .. "F"
        exs_tm1638.set_display(fah)
        sys.wait(600)
    end

    exs_tm1638.set_brightness(5)
    sys.wait(1000)
    exs_tm1638.clear()
end

local function run_main()
    log.info("tm1638_demo", "===== [7/7] 日期/时钟/温度 =====")

    show_date()
    sys.wait(300)
    show_clock()
    sys.wait(300)
    show_temperature()
end

-- 演示主函数（运行在协程中）
local function tm1638_demo_task_func()
    -- 初始化
    local init_ok = exs_tm1638.init({
        clk        = 1,
        dio        = 2,
        stb        = 17,
        bright     = 5,
        write_mode = "auto",
    })
    if not init_ok then
        log.error("tm1638_demo", "TM1638 初始化失败，请检查接线")
        return
    end

    log.info("tm1638_demo", "TM1638 初始化成功，版本:", exs_tm1638.version())

    -- HELLO 开始 → [1/7] → [2/7] → [3/7] → [4/7] → [5/7] → [6/7] → [7/7] → End
    exs_tm1638.set_display("HELLO")
    sys.wait(1000)

    demo_string()
    demo_leds()
    demo_brightness()
    demo_keys()
    demo_key_callback()
    demo_final_show()
    run_main()

    exs_tm1638.set_display("End")
    sys.wait(3000)
    log.info("tm1638_demo", "===== [演示完毕] =====")
end

sys.taskInit(tm1638_demo_task_func)
