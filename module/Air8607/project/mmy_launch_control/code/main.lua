--[[
@module  main
@summary 星河一号 · 发射指挥中心（Air8607 + 10.1 寸 1024x600 RGB + GT911 触摸）
@version 1.0.0
@date    2026.11.04
@board   Air8607 / Air1603
         硬件引脚与 module/Air8607/project/factory/config/eng_8607_10i_v0.lua 对齐：
           LCD 复位 pin_rst = 15   LCD 供电 pin_pwr = 17
           背光 PWM3（GPIO13）      触摸 I2C1（400kHz）pin_rst = 14 pin_int = 51
@usage
启动顺序：
1、power_on()     供电 / PWM3 占空比 0 / I2C1 引脚
2、exd.setup()    RGB 屏初始化（复位 + 时序 + 帧缓冲）
3、airui.init()   分辨率 + hzfont 中文字体
4、voice.init()   探测 TTS 后端（没有就静音，不影响界面）
5、ui.build()     装配整屏，ui.run() 起主循环
6、touch_init()   GT911 触摸绑定
7、backlight_on() 点亮背光
]]
PROJECT = "mmy_launch_control"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

local conf    = require "conf"
local theme   = require "theme"
local mission = require "mission"
local voice   = require "voice"
local ui      = require "ui_main"
local exd     = require "exd_air8607_rgb"

local SCREEN_W, SCREEN_H = conf.W, conf.H

-- ==================== 硬件 ====================
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

local function touch_init()
    if not tp or not tp.init then
        log.warn("main", "固件无 tp 库，触摸不可用")
        return false
    end
    local ok, dev = pcall(tp.init, "gt911", {
        port = 1, pin_rst = 14, pin_int = 51,
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

-- ==================== 语音桥 ====================
-- 任务引擎只管发"该说话了"，播报与否由 voice 自己决定
local function bind_voice()
    mission.subscribe(function(msg)
        if msg.type == "say" then
            voice.say(msg.text)
        elseif msg.type == "phase" then
            if msg.phase == "abort" then voice.stop() end
        end
    end)
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
    airui.font_load({
        type = "hzfont", size = conf.font.size,
        cache_size = conf.font.cache_size, antialias = conf.font.antialias,
    })

    local root = airui.container({
        x = 0, y = 0, w = SCREEN_W, h = SCREEN_H,
        color = theme.C.bg1, radius = 0,
    })

    voice.init()
    bind_voice()

    local page = ui.build(root)
    if not voice.ready() then
        page.bottom.mute_tx:set_text("语音 不可用")
        page.bottom.mute_tx:set_color(theme.C.ink3)
    end
    ui.run(page)

    touch_init()
    sys.wait(120)
    backlight_on()

    log.info("main", conf.name .. " 已就绪，等待发射指令")
end)

sys.run()
