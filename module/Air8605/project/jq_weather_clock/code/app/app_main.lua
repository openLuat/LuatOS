--[[
@module  app_main
@summary 应用主入口：上电时序 → 显示 → AirUI → 界面 → 触摸 → 背光
@version 1.0
@date    2026.11.08
@board   Air8605（Air1602 主控）+ 10.1 寸 RGB 1024x600 + GT911

=== 启动顺序（顺序不能换）===
1. power_on()      电源轨 / SD / 4G 复位 / 485 供电
2. net_boot.start() Airlink UART4G 上线（必须晚于第 1 步的 GPIO64 复位）
3. lcd.init()      display.init：RGB 时序 + FrameBuffer（AirUI 依赖它）
4. airui.init()    分辨率 + 旋转
5. font_load()     hzfont 内置字库（最重的一步，放在界面之前）
6. time_util.init  RTC 基准年 + 时区
7. weather         require 即启动天气任务（先上离线数据）
8. ui_main.start() 建界面 + 主循环
9. touch.init()    GT911 绑定（PC 模拟器跳过）
10. 背光点亮       **必须在首帧之后**：RGB 帧缓冲跨热复位不清屏，
                   提前开背光会把上一帧残留闪给用户

=== PC 模拟器 ===
rtos.bsp() == "PC" 时跳过全部硬件初始化，只跑界面逻辑，
方便先在电脑上对版式，再烧真机。
]]

local conf = require "conf"
local lcd = require "lcd_rgb"
local touch = require "touch_panel"
local time_util = require "time_util"
local ui_main = require "ui_main"
local net_boot = require "net_boot"
require "weather"          -- 侧效应：启动天气任务并注册 WEATHER_REQUEST 应答

local IS_PC = (rtos.bsp() == "PC")

-- ==================== 上电时序 ====================
local function power_on()
    -- 背光 PWM 先压到 0：PWM 引脚默认可能是高电平，上电瞬间背光会亮
    pcall(pwm.setup, conf.backlight.pwm_ch, conf.backlight.pwm_freq, 0)
    pcall(pwm.start, conf.backlight.pwm_ch)

    local bad = 0
    for i, step in ipairs(conf.power_on) do
        local ok1 = pcall(gpio.setup, step.pin, step.level)
        local ok2 = pcall(gpio.set, step.pin, step.level)
        if not (ok1 and ok2) then
            bad = bad + 1
            log.warn("app_main", "上电引脚失败", i, step.pin, step.level)
        end
        if step.delay then sys.wait(step.delay) end
    end
    log.info("app_main", "上电时序完成，失败", bad)
end

local function backlight_on()
    pcall(pwm.setup, conf.backlight.pwm_ch, conf.backlight.pwm_freq, conf.backlight.level)
    pcall(pwm.start, conf.backlight.pwm_ch)
    log.info("app_main", "背光点亮", conf.backlight.level .. "%")
end

-- ==================== 主流程 ====================
sys.taskInit(function()
    if not IS_PC then
        power_on()

        -- 4G 必须在 power_on 之后：GPIO64 的「高 50ms → 低 120ms」复位在上一步才走完。
        -- net_boot 内部用独立 task，握手过程不挡首屏。
        net_boot.start()

        local ok = lcd.init(conf.lcd)
        if not ok then
            log.error("app_main", "显示初始化失败")
            return
        end
    end

    if not airui.init(conf.W, conf.H) then
        log.error("app_main", "airui.init 失败（固件是否带 LUAT_USE_AIRUI）")
        return
    end
    airui.set_rotation(conf.rotation or 0)

    airui.font_load({
        type       = "hzfont",
        size       = conf.font.size,
        cache_size = conf.font.cache_size,
        antialias  = conf.font.antialias,
    })

    time_util.init()
    ui_main.start()

    if not IS_PC then
        local tp_conf = {
            port = conf.touch.port, pin_rst = conf.touch.pin_rst,
            pin_int = conf.touch.pin_int, w = conf.W, h = conf.H,
        }
        touch.init(tp_conf)
        backlight_on()
    end

    log.info("app_main", "桌面天气时钟已就绪", PROJECT, VERSION, os.date("%Y-%m-%d %H:%M:%S"))
end)
