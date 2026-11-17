--[[
@module main
@summary 音乐播放器 · AirUI 工程（合宙 Air8603，10 寸 1024×600 RGB 屏）
@version 1.0.0
@usage
设计稿 8603_music/index.html（1024×600）→ 本工程 1:1 重排：
  顶栏 + 左导航 + 四屏（播放 / 曲库 / 收藏 / 设置）+ 迷你播放条 + toast。

=== Air8603 屏幕点亮链路（与既有工程一致，勿改顺序）===
1. 供电轨上电：5V_EN=GPIO12 / 9V_EN=GPIO56 / 12V_EN=GPIO44 / 5VOUT_EN=GPIO52
2. display.init("custom", {...})：RGB 时序 1024×600 @50MHz
3. airui.init(1024, 600)：LVGL 引擎启动（必须先于任何控件创建和 font_load！）
4. 首帧上屏后开背光：PWM3 @1kHz 占空比 100（提前开会闪屏）
5. airui.font_load：矢量字库（必须 airui.init 之后，否则总线错误死机）
6. tp.init：GT911 触摸 I2C1（三步缺一步按钮 on_click 都不触发）
]]

PROJECT = "music_player_ui"
VERSION = "1.0.0"

local sys = require "sys"

local theme = require "theme"
local mock  = require "mock"
local page  = require "page_music"

local SCREEN_W, SCREEN_H = 1024, 600

sys.taskInit(function()
    log.info("main", "boot start")

    -- 1. 底板供电轨上电（顺序即依赖：5V → 9V → 12V → 5VOUT）
    pcall(gpio.setup, 12, 1)   -- 5V_EN
    pcall(gpio.setup, 56, 1)   -- 9V_EN
    sys.wait(100)
    pcall(gpio.setup, 44, 1)   -- 12V_EN
    pcall(gpio.setup, 52, 1)   -- 5VOUT_EN
    pcall(gpio.setup, 72, 0)   -- 网络模组 RST
    sys.wait(20)
    pcall(gpio.setup, 74, 1)   -- SD_EN（播放器必须挂 SD 卡）
    pcall(gpio.setup, 73, 1)   -- AUDIOPA_EN 开功放

    -- 2. RGB 屏硬件初始化
    local ok, err = pcall(display.init, "custom", {
        id = 0, interface = "rgb", pin_rst = 15,
        w = SCREEN_W, h = SCREEN_H,
        hbp = 140, hspw = 20, hfp = 160,
        vbp = 20, vspw = 3, vfp = 12,
        pclk_hz = 50 * 1000 * 1000,
    })
    log.info("main", "display.init", ok, err)

    -- 3. airui 引擎（必须最先）
    ok, err = pcall(airui.init, SCREEN_W, SCREEN_H)
    log.info("main", "airui.init", ok, err)
    pcall(airui.set_rotation, 0)

    -- 4. 首帧后开背光
    sys.wait(100)
    local pok, pret = pcall(pwm.open, 3, 1000, 100)
    if not pok or pret == false then
        pcall(pwm.setup, 3, 1000, 100)
        pcall(pwm.start, 3)
    end

    -- 5. 矢量字库（只允许 128/256/512/1024/2048）
    ok, err = pcall(airui.font_load, {
        type = "hzfont", size = 16, cache_size = 1024, antialias = 1 })
    log.info("main", "font_load", ok, err)

    -- 6. GT911 触摸（I2C1 轮询模式；RST 由内核驱动 tp_gt9xx_gpio_init 完成，
    --    脚本里不得再手拉 GPIO14，双复位会导致地址识别失败）
    pcall(i2c.setup, 1, 0, true)
    local tp_params = {
        port = 1, pin_rst = 14, pin_int = 51,
        w = SCREEN_W, h = SCREEN_H,
    }
    if tp.FALLING then tp_params.int_type = tp.FALLING end
    local dev
    ok, dev = pcall(tp.init, "gt911", tp_params)
    log.info("main", "tp.init", ok, dev)
    if dev then
        pcall(airui.device_bind_touch, dev)
    else
        log.error("main", "touch init failed, tapping disabled")
    end

    -- 7. 主题就位后开页（auto 模式按当前小时折算）
    local mode = mock.S.theme
    if mode == "auto" then
        local h = os.date("*t").hour
        mode = (h >= 7 and h < 18) and "day" or "night"
    end
    theme.apply(mode, mock.S.accent)

    pcall(function() math.randomseed(os.time() or 12345) end)
    ok, err = pcall(page.open)
    if not ok then
        log.error("main", "open page failed", err, debug.traceback())
    end
    log.info("main", "boot done")
end)

sys.run()
