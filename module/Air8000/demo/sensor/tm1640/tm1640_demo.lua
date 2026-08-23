--[[
@module  tm1640_demo
@summary TM1640 驱动芯片演示模块，包含所有功能的演示用例
@version 1.0
@date    2026.07.13
@author  江访
@usage
本文件包含 TM1640 的逐项功能演示和综合展示。
通过 exs_tm1640 扩展库的 API 逐一演示数码管显示、亮度调节等功能。
]]

-- 加载 exs_tm1640 扩展库
local exs_tm1640 = require "exs_tm1640"

-- 演示字符串显示（利用 16 位数码管）
local function demo_string()
    log.info("tm1640_demo", "===== [1/4] 字符串显示 =====")

    log.info("tm1640_demo", "显示 0123456789ABCDEF")
    exs_tm1640.clear()
    exs_tm1640.set_display("0123456789ABCDEF")
    sys.wait(2000)

    log.info("tm1640_demo", "显示 88.88")
    exs_tm1640.clear()
    exs_tm1640.set_display("88.88")
    sys.wait(1500)

    log.info("tm1640_demo", "从第 3 位开始显示 AbCd")
    exs_tm1640.clear()
    exs_tm1640.set_display("AbCd", 3)
    sys.wait(1500)

    log.info("tm1640_demo", "偏移显示 1234 在第 8 位")
    exs_tm1640.clear()
    exs_tm1640.set_display("1234", 8)
    sys.wait(1500)

    log.info("tm1640_demo", "从第 12 位显示 5678")
    exs_tm1640.clear()
    exs_tm1640.set_display("5678", 12)
    sys.wait(1500)

    exs_tm1640.clear()
    sys.wait(500)
end

-- 演示亮度调节
local function demo_brightness()
    log.info("tm1640_demo", "===== [2/4] 亮度调节 =====")

    exs_tm1640.clear()
    exs_tm1640.set_display("8888888888888888")
    sys.wait(500)

    for brightness = 0, 7 do
        log.info("tm1640_demo", "设置亮度:", brightness)
        exs_tm1640.set_brightness(brightness)
        sys.wait(800)
    end

    exs_tm1640.set_brightness(4)
    exs_tm1640.clear()
    sys.wait(500)
end

-- 综合演示
local function demo_final_show()
    log.info("tm1640_demo", "===== [3/4] 综合演示 =====")

    -- 倒计时
    for i = 5, 0, -1 do
        exs_tm1640.clear()
        exs_tm1640.set_display(string.format("%d", i))
        sys.wait(500)
    end

    -- HELLO 闪烁
    for i = 0, 3 do
        exs_tm1640.clear()
        exs_tm1640.set_display("HELLO")
        sys.wait(500)
        exs_tm1640.clear()
        sys.wait(300)
    end

    -- 全 8 显示加亮度渐变
    exs_tm1640.clear()
    exs_tm1640.set_display("8888888888888888")

    for i = 0, 7 do
        exs_tm1640.set_brightness(i)
        sys.wait(200)
    end

    sys.wait(1000)
    exs_tm1640.clear()

    log.info("tm1640_demo", "---- 综合演示结束 ----")
end

-- 展示日期：16 位显示 "26-07-13 08:30"
local function show_datetime()
    log.info("tm1640_demo", "日期时钟展示: 26-07-13 08:30")
    exs_tm1640.set_display("26-07-13 08:30")
    sys.wait(4000)
    exs_tm1640.clear()
end

-- 展示时间：模拟走时 "08-30-00" ~ "08-30-09"
local function show_clock()
    exs_tm1640.clear()
    sys.wait(200)
    log.info("tm1640_demo", "时钟展示: 08-30-00 ~ 08-30-09")
    for sec = 0, 9 do
        exs_tm1640.set_display(string.format("08-30-%02d", sec))
        sys.wait(500)
    end
end

-- 展示温度：摄氏度用 "°C"，华氏度用 "°F"
local function show_temperature()
    exs_tm1640.clear()
    sys.wait(200)
    local DEGREE = "°"
    for temp = 25, 32 do
        local cel = string.format("%02d", temp) .. DEGREE .. "C"
        exs_tm1640.set_display(cel)
        local bright = math.floor((temp - 25) / 7 * 7 + 0.5)
        if bright < 0 then bright = 0 end
        if bright > 7 then bright = 7 end
        exs_tm1640.set_brightness(bright)
        sys.wait(800)
    end

    for temp = 77, 90, 2 do
        local fah = string.format("%02d", temp) .. DEGREE .. "F"
        exs_tm1640.set_display(fah)
        sys.wait(600)
    end

    exs_tm1640.set_brightness(5)
    sys.wait(1000)
    exs_tm1640.clear()
end

local function run_main()
    log.info("tm1640_demo", "===== [4/4] 日期/时钟/温度 =====")

    show_datetime()
    sys.wait(300)
    show_clock()
    sys.wait(300)
    show_temperature()
end

-- 演示主函数（运行在协程中）
local function tm1640_demo_task_func()
    -- 初始化（2-wire：CLK + DIN，无 STB）
    local result = exs_tm1640.setup({
        clk    = 1,
        din    = 2,
        bright = 5,
    })
    if not result then
        log.error("tm1640_demo", "TM1640 初始化失败，请检查接线")
        return
    end

    log.info("tm1640_demo", "TM1640 初始化成功，版本:", exs_tm1640.version())

    -- HELLO → [1/4] → [2/4] → [3/4] → [4/4] → End
    exs_tm1640.set_display("HELLO")
    sys.wait(1000)

    demo_string()
    demo_brightness()
    demo_final_show()
    run_main()

    exs_tm1640.set_display("End")
    sys.wait(3000)
    log.info("tm1640_demo", "===== [演示完毕] =====")
end

sys.taskInit(tm1640_demo_task_func)
