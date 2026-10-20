--[[
@module  display_test
@summary Air8602 7寸 EK73215+EK79001 显示测试模块
@version 1.0
@date    2026.10.08
@author  江访
@usage
本文件为 7 寸 EK73215+EK79001 显示测试模块，核心测试流程为：
1、power_on()     —— 供电与背光 PWM3 上电占空比 0 配置，本板 LCD_DISP = GPIO15，用户按原理图自行拉高
2、exd.setup()    —— 显示初始化，扩展库仅做显示IC初始化（复位 + RGB 时序 + 帧缓冲）
3、draw_ui()      —— 界面绘制，深色背景 + 型号标题
4、backlight_on() —— 背光点亮，PWM3，界面就绪后用户自行点亮

重要：供电、背光均由本 demo 自行控制，显示IC初始化扩展库只负责显示 IC 初始化，
不操作供电引脚 pin_pwr、不操作背光引脚 pin_bl，显示初始化完成也不会自动开背光。

EK73215+EK79001 为免初始化显示IC组合（显示侧双芯片）：无寄存器序列，扩展库只做复位 + RGB 时序配置。
板级复位脚 pin_rst 必传，本板 LCD_DISP = GPIO15 兼 LCD 复位脚。
本屏只支持显示，不支持触摸。

测试现象：深色背景 + 型号标题。
]]

-- 加载 EK73215+EK79001 显示IC初始化扩展库
local exd = require "exd_ek79001_rgb"

-- 本板屏幕参数（EK73215+EK79001 7寸 1024x600）
local SCREEN_W = 1024
local SCREEN_H = 600

-- 供电与背光 PWM3 上电占空比 0 配置
-- LCD 供电/显示使能引脚由用户按底板原理图控制，扩展库不操作 pin_pwr
-- 本板 LCD_DISP = GPIO15（兼 LCD 复位脚，显示初始化内部会做复位时序）
local function power_on()
    -- 背光 PWM3 上电占空比 0
    pwm.setup(3, 1000, 0)  -- 通道 3，1kHz，占空比 0
    pwm.start(3)
    -- LCD_DISP = GPIO15（兼 LCD 复位脚，显示初始化内部会做复位时序）
    gpio.setup(15, 1)   -- 输出高电平，使能 LCD 显示
    sys.wait(100)       -- 等供电稳定
end

-- 背光点亮
-- 背光引脚由用户控制，扩展库不操作 pin_bl，显示初始化完成不会自动开背光
-- 本板背光 = PWM3 调光
local function backlight_on()
    local ok = pwm.setup(3, 1000, 100)  -- 通道 3，1kHz，100% 亮度
    if ok then
        pwm.start(3)
        log.info("display_test", "背光已点亮")
    else
        log.error("display_test", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

-- 界面绘制：深色全屏背景 + 型号标题
local function draw_ui()
    -- 深色全屏背景
    airui.shape({
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        items = {
            { type = "rect", x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
              fill = true, fill_color = 0x101828, color = 0x101828 },
        },
    })
    -- 型号标题
    airui.label({
        x = 0, y = math.floor(SCREEN_H / 2) - 18, w = SCREEN_W, h = 36,
        text = "Air8602 7寸 EK73215+EK79001 显示测试",
        font_size = 28, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER,
    })
end

-- 测试主任务（运行在协程中）：供电 → 显示初始化 → 界面绘制 → 背光点亮
local function display_test_task_func()
    -- 1、供电配置（自行控制）
    power_on()

    -- 2、显示初始化（扩展库，仅显示IC初始化）
    --    EK73215+EK79001 不设板级默认参数，pin_rst 必传
    --    本板 LCD_DISP = GPIO15 兼 LCD 复位脚，屏幕参数（7寸 1024x600/时序）全默认
    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("display_test", "显示初始化失败", info)
        return
    end
    log.info("display_test", "显示初始化完成", info.backend, info.w, info.h)

    -- 3、UI 初始化与界面绘制
    airui.init(info.w, info.h)
    airui.set_rotation(0)
    airui.font_load({ type = "hzfont", size = 24, cache_size = 1024, antialias = 1 })
    draw_ui()

    -- 4、背光点亮（自行控制，界面就绪后点亮避免花屏）
    backlight_on()
    log.info("display_test", "显示测试就绪")
end

sys.taskInit(display_test_task_func)
