--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 开机自检 + 启动编排
@version 1.0
@date    2026.10.26
@author  江访
@usage
require 即执行，main.lua 调用 require "app_main" 时完成：
1、power_on()     供电 / 背光 PWM3 占空比 0 / I2C 引脚；
2、exd.setup()    显示初始化（复位 + RGB 时序 + 帧缓冲）；
3、airui.init     分辨率 + hzfont 矢量字库 + 旋转；
4、boot_logo()    开机画面 + 自检进度条；
5、ui.build()     搭监测大屏，随后绑定触摸（必须早于主循环）；
6、ui.run()       启动主循环；
7、backlight_on() 界面就绪后点亮背光，防上电花屏。
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

-- GT911 触摸（大屏没有交互元素，失败也不影响显示）
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

-- 开机画面：徽章 + 标题 + 自检进度条（每帧只重画进度小条）
local function boot_logo()
    local root = airui.container({ x = 0, y = 0, w = SCREEN_W, h = SCREEN_H })

    airui.shape({
        parent = root, x = 397, y = 110, w = 230, h = 230,
        items = {
            -- 圆形徽章底 + 双描边
            { type = "circle", cx = 115, cy = 115, r = 112, color = 0x0B3D66, width = 2, fill = true, opacity = 220 },
            { type = "circle", cx = 115, cy = 115, r = 112, color = 0x1C63A0, width = 6 },
            { type = "circle", cx = 115, cy = 115, r = 103, color = 0x2372B8, width = 2, opacity = 160 },
            -- 屏幕外框（圆角矩形）
            { type = "rect", x = 43, y = 65, w = 145, h = 105,
              rounded = true, radius = 10, color = 0x2D7CC4, width = 3, fill = true, fill_color = 0x0D2B4A, fill_opacity = 255 },
            -- 负荷曲线三段折线
            { type = "line", x1 = 53, y1 = 108, x2 = 68, y2 = 108, color = 0x2FE0F0, width = 3 },
            { type = "line", x1 = 68, y1 = 108, x2 = 83, y2 = 93, color = 0x2FE0F0, width = 3 },
            { type = "line", x1 = 83, y1 = 93, x2 = 98, y2 = 118, color = 0x2FE0F0, width = 3 },
            { type = "line", x1 = 98, y1 = 118, x2 = 113, y2 = 98, color = 0x2FE0F0, width = 3 },
            { type = "line", x1 = 113, y1 = 98, x2 = 128, y2 = 108, color = 0x2FE0F0, width = 3 },
            -- 断路器符号（两端点 + 连线）
            { type = "circle", cx = 148, cy = 102, r = 4, color = 0x2FE0F0, width = 2, fill = true, fill_opacity = 255 },
            { type = "circle", cx = 148, cy = 128, r = 4, color = 0x2FE0F0, width = 2, fill = true, fill_opacity = 255 },
            { type = "line", x1 = 148, y1 = 102, x2 = 148, y2 = 128, color = 0x2FE0F0, width = 3 },
            -- 电池底座 + 电量刻度
            { type = "rect", x = 93, y = 182, w = 45, h = 30, rounded = true, radius = 6,
              color = 0x2D7CC4, width = 3, fill = true, fill_color = 0x0D2B4A, fill_opacity = 255 },
            { type = "rect", x = 101, y = 190, w = 9, h = 14, color = 0x2FE0F0, width = 1, fill = true, fill_opacity = 255 },
            { type = "rect", x = 114, y = 190, w = 9, h = 14, color = 0x2FE0F0, width = 1, fill = true, fill_opacity = 255 },
            { type = "rect", x = 127, y = 190, w = 9, h = 14, color = 0x2FE0F0, width = 1, fill = true, fill_opacity = 255 },
        }
    })

    airui.label({ parent = root, x = 50, y = 368, w = 924, h = 36,
                  text = "智慧配电房运维监测", font_size = 32,
                  color = 0x77D8FF, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = root, x = 50, y = 410, w = 924, h = 24,
                  text = "SMART SUBSTATION O&M TERMINAL", font_size = 16,
                  color = 0x88B8D8, align = airui.TEXT_ALIGN_CENTER })

    -- 自检进度条：底板 + 前景（前景每帧只重画 712x24 小条）
    local bar_x, bar_y, bar_w, bar_h = 156, 472, 712, 28
    airui.shape({
        parent = root, x = bar_x, y = bar_y, w = bar_w, h = bar_h,
        items = {
            { type = "rect", x = 0, y = 0, w = bar_w, h = bar_h,
              rounded = true, radius = 6, color = 0x1C63A0, width = 2,
              fill = true, fill_color = 0x0A2E52, fill_opacity = 255 },
        }
    })
    local fg = airui.shape({ parent = root, x = bar_x + 4, y = bar_y + 4, w = bar_w - 8, h = bar_h - 8, items = {} })
    airui.label({ parent = root, x = 50, y = 506, w = 924, h = 20,
                  text = "正在初始化遥测数据与通信链路", font_size = 14,
                  color = 0x88B8D8, align = airui.TEXT_ALIGN_CENTER })

    local inner_w, inner_h = bar_w - 8, bar_h - 8
    for pos = 25, 100, 25 do
        sys.wait(180)
        local w = math.floor(inner_w * pos / 100)
        fg:set_items({
            { type = "rect", x = 0, y = 0, w = w, h = inner_h,
              rounded = true, radius = 5, fill = true, fill_color = 0x1E90FF, fill_opacity = 255 },
        })
    end
    sys.wait(200)
    root:hide()
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
    -- hzfont 矢量字库：只加载一次，之后各 label 用 font_size 缩放
    local ok2, err2 = airui.font_load({
        type = "hzfont", size = 16, cache_size = 2048, antialias = 1,
    })
    log.info("app_main", "hzfont", ok2, err2)

    boot_logo()
    ui.build()
    touch_init()

    sys.taskInit(function()
        ui.run()
    end)

    sys.wait(220)
    backlight_on()
    log.info("app_main", "智慧配电房运维监测已启动")
end)
