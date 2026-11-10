--[[
@module  main
@summary SkyLift 雪山索道运营大屏（Air8607 + 10.1 寸 1024x600 RGB + GT911 触摸）
@version 1.0.0
@date    2026.11.06
@board   Air8607 / Air1603
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst = 14 pin_int = 51
@usage
启动顺序：
1、power_on()      供电 / PWM3 占空比 0 / I2C1 引脚
2、exd.setup()     显示 IC 初始化（复位 + RGB 时序 + 帧缓冲）
3、airui.init()    分辨率 + 逐档 hzfont 中文字库
4、app.start()     构建顶部栏与主页（运营总览）
5、touch_init()    GT911 初始化 + airui 绑定
6、backlight_on()  点亮背光，防上电花屏
]]
PROJECT = "sky_lift"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

local conf  = require("conf")
local theme = require("theme")
local app   = require("app")
local exd   = require("exd_air8607_rgb")

local SCREEN_W, SCREEN_H = conf.W, conf.H

-- 界面用到的字号必须全部加载，漏了会渲染成方框或回退字形
local FONT_SIZES = { theme.SZ.xs, theme.SZ.s, theme.SZ.m, theme.SZ.l, theme.SZ.xl, theme.SZ.hero }

local function power_on()
    pcall(function()
        pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, 0)
        pwm.start(conf.backlight.pwm_ch)
    end)
    pcall(function()
        gpio.setup(17, 0)   -- LCD 供电使能（低有效）
        gpio.setup(15, 1)   -- LCD 复位释放
    end)
    pcall(function()
        i2c.setup(1, i2c.FAST)
    end)
    sys.wait(100)
end

local function backlight_on()
    local duty = conf.backlight.default
    local ok = pcall(function()
        pwm.setup(conf.backlight.pwm_ch, conf.backlight.freq, duty)
        pwm.start(conf.backlight.pwm_ch)
    end)
    log.info("main", ok and ("背光已点亮 " .. duty .. "%") or "背光初始化失败")
end

--[[GT911 触摸初始化
w/h 必须给：缺了会让 input 适配器以 EINVAL 静默拒绝，
表现为"日志说初始化完成但点不动"。]]
local function touch_init()
    if not tp or not tp.init then
        log.warn("main", "固件无 tp 库，触摸不可用")
        return false
    end
    local t = conf.touch
    local ok, dev = pcall(tp.init, "gt911", {
        port = t.port, pin_rst = t.pin_rst, pin_int = t.pin_int,
        int_type = tp.FALLING, w = SCREEN_W, h = SCREEN_H,
    })
    if ok and dev then
        if airui.device_bind_touch then
            pcall(airui.device_bind_touch, dev)
        end
        log.info("main", "GT911 触摸初始化完成")
        return true
    end
    log.error("main", "触摸初始化失败", tostring(dev))
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

    if not airui.init(SCREEN_W, SCREEN_H) then
        log.error("main", "airui.init 失败")
        return
    end
    airui.set_rotation(0)

    -- 逐档加载：12/14/16/20/26/40
    for _, sz in ipairs(FONT_SIZES) do
        airui.font_load({
            type = "hzfont", size = sz,
            cache_size = conf.font.cache_size, antialias = conf.font.antialias,
        })
    end

    local root = airui.container({
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        color = theme.C.bg0, radius = 0,
    })
    app.start(root)

    touch_init()
    sys.wait(120)
    backlight_on()

    log.info("main", conf.name .. " 已就绪", conf.resort.site)
end)

sys.run()
