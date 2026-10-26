--[[
@module  app_main
@summary 应用主入口：硬件初始化 + 启动编排
@author  王世豪
@version 1.0
@date    2026.10.26
@board   Air8607（Air1603）+ 10寸 RGB 1024x600 + GT911 电容触摸
@usage
require 即执行：
1、power_on()      背光 PWM3 占空比 0、LCD 供电、SD_EN、功放关断、I2C1 轮询
2、exd.setup()     显示初始化
3、airui.init()    分辨率 + 旋转 + 中文字库
4、line_sim.init() 虚拟产线数据源
5、ui_main.build() 建看板
6、touch_init()    GT911 绑定
7、背光点亮
8、每秒：推进产线 + 刷新界面
@note PC 分支
rtos.bsp() == "PC" 时跳过全部硬件初始化，虚拟产线照常跑，方便电脑上验证。
]]
local conf = require "conf"
local theme = require "theme"
local ui_main = require "ui_main"
local line_sim = require "line_sim"
local rtc_util = require "rtc_util"

local SW, SH = conf.W, conf.H
local C = theme.C

local IS_PC = false
do
    local ok, bsp = pcall(function() return rtos.bsp() end)
    if ok and bsp == "PC" then IS_PC = true end
    log.info("app_main", "运行环境检测", "rtos.bsp() =", tostring(bsp), "=> IS_PC =", tostring(IS_PC))
end

-- ==================== 上电时序（仅真机）====================
local function power_on()
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
    pwm.start(conf.backlight.pwm_ch)

    gpio.setup(17, 0)      -- LCD 供电使能（低有效）
    gpio.setup(15, 1)      -- LCD_DISP
    gpio.setup(74, 1)      -- SD_EN 上电
    gpio.setup(73, 0)      -- 功放 PA 关断（报警音需要时再开）

    i2c.setup(1, 0, true)  -- GT911 必须轮询模式
    sys.wait(120)
end

local function backlight_on()
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, conf.backlight.duty)
    pwm.start(conf.backlight.pwm_ch)
    log.info("app_main", "背光已点亮", conf.backlight.duty .. "%")
end

local function touch_init()
    for attempt = 1, 2 do
        local dev = tp.init("gt911", {
            port = conf.touch.port,
            pin_rst = conf.touch.pin_rst,
            pin_int = conf.touch.pin_int,
            int_type = tp.FALLING,
            w = SW,
            h = SH,
        })
        if dev then
            airui.device_bind_touch(dev)
            log.info("app_main", "GT911 触摸初始化完成")
            return true
        end
        log.warn("app_main", "GT911 未成功，200ms 后重试", attempt)
        sys.wait(200)
    end
    log.error("app_main", "触摸初始化失败")
    return false
end

-- ==================== 主流程 ====================
sys.taskInit(function()
    if not IS_PC then power_on() end

    if not IS_PC then
        local exd = require "exd_air8607_rgb"
        local ok, info = exd.setup({ pin_rst = conf.display.pin_rst })
        if not ok then
            log.error("app_main", "显示初始化失败", info)
            return
        end
        log.info("app_main", "显示初始化完成", info.backend, info.w, info.h)
    end

    if not airui.init(SW, SH) then
        log.error("app_main", "airui.init 失败")
        return
    end
    airui.set_rotation(conf.display.rotation)
    airui.font_load({
        type = "hzfont",
        size = conf.font.size,
        cache_size = conf.font.cache_size,
        antialias = conf.font.antialias,
    })

    local page = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg1, radius = 0, border_width = 0,
    })
    theme.gradient(page, 0, 0, SW, SH, C.bg1, C.bg2, 16)

    -- 数据源先就绪，界面构建时就能拿到初始值
    line_sim.init()
    ui_main.build(page)
    ui_main.refresh()

    if not IS_PC then
        touch_init()
        backlight_on()
    end

    rtc_util.init()
    sys.timerLoopStart(ui_main.refresh, conf.tick.ui)

    log.info("app_main", "Andon 看板已就绪", PROJECT, VERSION, os.date("%Y-%m-%d %H:%M:%S"))
end)
