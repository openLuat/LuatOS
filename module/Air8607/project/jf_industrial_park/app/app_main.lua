--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排
@version 1.0
@date    2026.10.25
@author  江访
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()     供电 / 背光 PWM3 占空比 0 / I2C 引脚；
2、exd.setup()    显示初始化（复位 + RGB 时序 + 帧缓冲）；
3、airui.init     分辨率 + hzfont 矢量字库 + 旋转；
4、ui.build()     搭界面，随后绑定触摸（必须早于主循环）；触摸只是可选项：
                  园区大屏是纯展示，没有可点元素，GT911 初始化失败不阻塞显示；
5、ui.run()       启动主循环；
6、backlight_on() 界面就绪后点亮背光，防上电花屏。
]]

local exd = require "exd_air8607_rgb"
local ui = require "ui_main"

local SCREEN_W, SCREEN_H = 1024, 600

local function power_on()
    pwm.setup(3, 1000, 0)
    pwm.start(3)
    gpio.setup(17, 0)     -- LCD 供电使能（低有效）
    gpio.setup(15, 1)     -- 显示使能 / 复位脚
    i2c.setup(1, i2c.FAST)
    sys.wait(100)
end

local function backlight_on()
    if pwm.setup(3, 1000, 100) then
        pwm.start(3)
        log.info("app_main", "背光已点亮")
    else
        log.error("app_main", "背光初始化失败，请确认 PWM 通道与原理图一致")
    end
end

-- GT911 触摸（园区大屏没有交互元素，失败也不影响显示）
local function touch_init()
    local dev = tp.init("gt911", {
        port = 1, pin_rst = 14, pin_int = 51, int_type = tp.FALLING,
        w = SCREEN_W, h = SCREEN_H,
    })
    if dev then
        airui.device_bind_touch(dev)
        log.info("app_main", "GT911 触摸初始化完成")
        return true
    end
    log.warn("app_main", "触摸初始化失败，纯展示模式继续运行")
    return false
end

sys.taskInit(function()
    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("app_main", "显示初始化失败", info)
        return
    end
    log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)

    airui.init(SCREEN_W, SCREEN_H)
    airui.set_rotation(0)
    airui.font_load({ type = "hzfont", size = 16, cache_size = 2048, antialias = 1 })

    ui.build()
    touch_init()

    sys.taskInit(function()
        ui.run()
    end)

    sys.wait(220)
    backlight_on()
    log.info("app_main", "智慧工业园区管理平台已启动")
end)
