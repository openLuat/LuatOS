--[[
@module main
@summary AIR KTV 智能点歌系统 · AirUI 界面演示入口
         合宙 Air8603 / Air1603，1024×600 RGB565 电容触摸屏

点亮顺序（勿改）：
1. 供电轨 GPIO12/56/44/52/74
2. display.init("custom", RGB 时序)
3. airui.init(1024,600)         —— 必须早于任何控件与 font_load
4. 首帧后 PWM3 背光
5. airui.font_load(hzfont)      —— 中文与拼音键盘的前提
6. tp.init("gt911") → airui.device_bind_touch
7. theme.apply → page.open → sys.run

本工程只做 UI 演示：数据全部来自 mock.lua，不接音频与网络。
]]

PROJECT = "air_ktv_ui"
VERSION = "2.6.0"

local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"
local page  = require "page_ktv"

local W, H = 1024, 600

pcall(function() if wdt and wdt.init then wdt.init(60000) end end)
sys.taskInit(function()
    while true do
        sys.wait(1000)
        pcall(function() if wdt and wdt.feed then wdt.feed() end end)
    end
end)

sys.taskInit(function()
    log.info("ktv", "boot start")
    local t0 = mcu.ticks()

    -- 1. 供电轨
    pcall(gpio.setup, 12, 1)
    pcall(gpio.setup, 56, 1)
    sys.wait(100)
    pcall(gpio.setup, 44, 1)
    pcall(gpio.setup, 52, 1)
    pcall(gpio.setup, 72, 0)
    sys.wait(20)
    pcall(gpio.setup, 74, 1)

    -- 2. RGB 屏
    local ok, err = pcall(display.init, "custom", {
        id=0, interface="rgb", pin_rst=15,
        w=W, h=H, hbp=140, hspw=20, hfp=160,
        vbp=20, vspw=3, vfp=12, pclk_hz=50*1000*1000,
    })
    log.info("ktv", "display.init", ok, err, "t=", mcu.ticks()-t0)

    -- 3. AirUI
    ok, err = pcall(airui.init, W, H)
    log.info("ktv", "airui.init", ok, err)
    pcall(airui.set_rotation, 0)

    -- 3.5 先铺深色全屏底，再开背光：避免 LVGL 默认白底在初始化期间闪白屏
    pcall(function()
        airui.container({parent=airui.screen,x=0,y=0,w=W,h=H,color=0x10131D,radius=0})
    end)
    sys.wait(60)

    -- 4. 背光
    local pok, pret = pcall(pwm.open, 3, 1000, 85)
    if not pok or pret == false then
        pcall(pwm.setup, 3, 1000, 85)
        pcall(pwm.start, 3)
    end

    -- 5. 矢量中文字库：path=nil 用固件内置 ttf（拼音键盘需要）
    ok, err = pcall(airui.font_load, {
        type="hzfont", path=nil, size=16, cache_size=1024, antialias=1 })
    log.info("ktv", "font_load", ok, err, "t=", mcu.ticks()-t0)

    -- 6. GT911 触摸
    pcall(i2c.setup, 1, 0, true)
    local p = {port=1, pin_rst=14, pin_int=51, w=W, h=H}
    if tp.FALLING then p.int_type = tp.FALLING end
    local dev
    ok, dev = pcall(tp.init, "gt911", p)
    log.info("ktv", "tp.init", ok, dev, "t=", mcu.ticks()-t0)
    if dev then pcall(airui.device_bind_touch, dev)
    else log.error("ktv", "touch init failed") end

    -- 7. 开页
    theme.apply(mock.S.mode, mock.S.theme)
    ok, err = pcall(page.open)
    if not ok then log.error("ktv", "open failed", err, debug.traceback()) end
    log.info("ktv", "boot done", "t=", mcu.ticks()-t0)
end)

sys.run()
