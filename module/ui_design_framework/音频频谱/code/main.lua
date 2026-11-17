--[[
@module main
@summary 音频频谱 · 音乐律动 - AirUI 工程（合宙 Engine Air8603，10寸 1024×600 RGB 屏）
@version 1.0.0
@usage
设计稿 audio_spectrum_ui/preview.html（1024×800）→ 本工程按 1024×600 重排。
三种可视化模式（环形 / 柱状 / 波形）全部动态跳动，且每一块都可点击。

=== Air8603 屏幕点亮链路（与既有工程完全一致，勿改顺序）===
1. 供电轨上电：5V_EN=GPIO12 / 9V_EN=GPIO56 / 12V_EN=GPIO44 / 5VOUT_EN=GPIO52
2. display.init("custom", {...})：RGB 时序 1024×600 @50MHz
3. airui.init(1024, 600)：LVGL 引擎启动（必须先于任何控件创建和 font_load！）
4. 首帧上屏后开背光：PWM3 @1kHz 占空比 100（提前开会闪屏）
5. airui.font_load：矢量字库（必须在 airui.init 之后，否则总线错误死机）
6. tp.init：GT911 触摸 I2C1（三步缺一步按钮 on_click 都不触发）
]]

PROJECT = "audio_spectrum_ui"
VERSION = "1.0.0"

local sys   = require "sys"
local exwin = require "exwin"

local theme = require "theme"
require "page_spectrum"

-- Air8603 10寸 1024×600 RGB 屏（官方工厂固件实测参数）
local SCREEN_W, SCREEN_H = 1024, 600

sys.taskInit(function()
    log.info("main", "boot start")

    -- 1. 底板供电轨上电
    pcall(gpio.setup, 12, 1)  -- 5V_EN
    pcall(gpio.setup, 56, 1)  -- 9V_EN
    sys.wait(100)
    pcall(gpio.setup, 44, 1)  -- 12V_EN
    pcall(gpio.setup, 52, 1)  -- 5VOUT_EN
    log.info("main", "power rails on")

    -- 2. RGB 屏硬件初始化
    local ok, err = pcall(display.init, "custom", {
        id        = 0,
        interface = "rgb",
        pin_rst   = 15,
        w         = SCREEN_W,
        h         = SCREEN_H,
        hbp = 140, hspw = 20, hfp = 160,
        vbp = 20,  vspw = 3,  vfp = 12,
        bus_speed = 50 * 1000 * 1000,
    })
    log.info("main", "display.init ok=" .. tostring(ok) .. " err=" .. tostring(err))

    -- 3. airui 引擎初始化（必须最先）
    ok, err = pcall(airui.init, SCREEN_W, SCREEN_H)
    log.info("main", "airui.init ok=" .. tostring(ok) .. " err=" .. tostring(err))
    pcall(airui.set_rotation, 0)

    -- 4. 首帧上屏后开背光
    sys.wait(100)
    local pok, pret = pcall(pwm.open, 3, 1000, 100)
    if not pok or pret == false then
        pcall(pwm.setup, 3, 1000, 100)
        pcall(pwm.start, 3)
    end
    log.info("main", "backlight pwm3: " .. tostring(pok) .. "/" .. tostring(pret))

    -- 5. 矢量字库（必须 airui.init 之后；cache_size 只允许 128/256/512/1024/2048）
    ok, err = pcall(airui.font_load, {
        type = "hzfont", size = 16, cache_size = 1024, antialias = 1 })
    log.info("main", "font_load ok=" .. tostring(ok) .. " err=" .. tostring(err))

    -- 6. GT911 触摸
    pcall(i2c.setup, 1, i2c.SLOW)
    pcall(gpio.setup, 14, 0)
    pcall(gpio.close, 14)
    local dev
    ok, dev = pcall(tp.init, "gt911", {
        port = 1, pin_rst = 14, pin_int = 51,
        int_type = 1, w = SCREEN_W, h = SCREEN_H })
    log.info("main", "tp.init ok=" .. tostring(ok) .. " dev=" .. tostring(dev))
    if dev then
        pcall(airui.device_bind_touch, dev)
        log.info("main", "touch bound to airui")
    else
        log.error("main", "touch init failed, all tapping disabled")
    end

    -- 7. 打开页面（频谱抖动用随机数，先播种）
    pcall(function() math.randomseed(os.time() and os.time() or 12345) end)
    log.info("main", "open_page ...")
    ok, err = pcall(theme.open_page, 1)
    if not ok then
        log.error("main", "open_page failed: " .. tostring(err)
            .. "\n" .. tostring(debug.traceback()))
    end
    log.info("main", "boot done")
end)

-- 调度器：必须是最后一行
sys.run()
