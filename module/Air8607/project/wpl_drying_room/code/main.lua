--[[
@module  main
@summary 烘干室智能控制大屏入口（Air8607 10.1寸 1024x600）
@version 1.0
@date    2026.10.24
@board   Air8607（Air1603）+ 10寸 RGB 1024x600（免序列）+ GT911 电容触摸
]]
PROJECT = "wpl_drying_room"
VERSION = "1.0.0"

local conf = require "conf"
local exd = require "exd_air8607_rgb"
local app = require "app"

local SW, SH = conf.W, conf.H

local function power_on()
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
    pwm.start(conf.backlight.pwm_ch)

    gpio.setup(17, 0)   -- LCD 供电（低有效）
    gpio.setup(15, 1)   -- DISP
    gpio.setup(73, 0)   -- 功放关断

    i2c.setup(1, i2c.FAST)
    sys.wait(120)
end

local function backlight_on()
    local b = conf.backlight.default
    pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, b)
    pwm.start(conf.backlight.pwm_ch)
    log.info("main", "背光已点亮", b .. "%")
end

local function touch_init()
    local dev = tp.init("gt911", {
        port = 1,
        pin_rst = 14,
        pin_int = 51,
        int_type = tp.FALLING,
        w = SW,
        h = SH,
    })
    if dev then
        airui.device_bind_touch(dev)
        log.info("main", "GT911 触摸初始化完成")
        return true
    end
    log.error("main", "触摸初始化失败")
    return false
end

sys.taskInit(function()
    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("main", "显示初始化失败", info)
        return
    end
    log.info("main", "显示初始化完成", info.backend, info.w, info.h)
    if info.backend ~= "display" then
        log.warn("main", "固件缺少 display 核心库（当前走旧 lcd 后端），建议升级 Air1603 V1028")
    end

    if not airui.init(SW, SH) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)
    airui.font_load({
        type = "hzfont",
        size = conf.font.size,
        cache_size = conf.font.cache_size,
        antialias = conf.font.antialias,
    })

    app.start()
    touch_init()

    backlight_on()
    log.info("main", conf.name .. " 已就绪")
end)

sys.run()
