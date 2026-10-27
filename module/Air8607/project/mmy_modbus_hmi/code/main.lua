--[[
@module  main
@summary Modbus 工业中控大屏入口（Air8607 + AirLCD_1090 1024x600）
@version 1.0.0
@date    2026.10.25
@board   Air8607（Air1603）+ AirLCD_1090（9寸 RGB 1024×600 / JD9165BA / GT911）
]]
PROJECT = "modbus_hmi"
VERSION = "1.0.0"

local conf = require "conf"
local exd = require "exd_jd9165ba_rgb"
local app = require "app"

local SW, SH = conf.W, conf.H
local IS_PC = (rtos and rtos.bsp and rtos.bsp() == "PC")

-- ==================== 板级上电 ====================
local function power_on()
    if IS_PC then return end
    pcall(function()
        pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
        pwm.start(conf.backlight.pwm_ch)
        gpio.setup(17, 0)   -- LCD 供电使能（低有效）
        gpio.setup(15, 1)   -- LCD_DISP / 复位
        gpio.setup(73, 0)   -- 功放关断
        i2c.setup(1, i2c.FAST)
    end)
    sys.wait(120)
end

local function backlight_on()
    local b = conf.backlight.default
    if not IS_PC then
        pcall(function()
            pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, b)
            pwm.start(conf.backlight.pwm_ch)
        end)
    end
    log.info("main", "背光已点亮", b .. "%")
end

local function touch_init()
    if IS_PC then
        log.info("main", "PC 模拟器由 SDL 提供指针输入，跳过 GT911")
        return false
    end
    local ok, dev = pcall(function()
        return tp.init("gt911", {
            port = 1,
            pin_rst = 14,
            pin_int = 51,
            int_type = tp.FALLING,
            w = SW,
            h = SH,
        })
    end)
    if ok and dev then
        pcall(function() airui.device_bind_touch(dev) end)
        log.info("main", "GT911 触摸初始化完成")
        return true
    end
    log.error("main", "触摸初始化失败，界面不可触控", dev)
    return false
end

sys.taskInit(function()
    power_on()

    local ok, info = exd.setup({ pin_rst = 15 })
    if not ok then
        log.error("main", "显示初始化失败", info)
        if not IS_PC then return end
    else
        log.info("main", "显示初始化完成", info.backend, info.w, info.h, info.ic)
    end

    if not airui.init(SW, SH) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)
    pcall(function()
        airui.font_load({
            type = "hzfont",
            size = conf.font.size,
            cache_size = conf.font.cache_size,
            antialias = conf.font.antialias,
        })
    end)

    app.start()
    touch_init()
    backlight_on()

    log.info("main", conf.name .. " v" .. VERSION .. " 已就绪",
        "传输方式=" .. (conf.comm.transport or "sim"))
end)

sys.run()
