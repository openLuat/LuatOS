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

=== 看门狗（参考 TMR_Batching_System）===
- 内部硬狗：wdt.init(60000)，独立心跳 task 每秒 wdt.feed()；
- 外置 Air153D：GPIO57 → NPN → WTDOG，库内部自动喂狗，解决约 10 分钟周期性整机复位；
  内部 wdt 喂不到这颗外部芯片，两者并存且互不替代。

=== 音频 ===
- audio/demo_10s.mp3（内容为 6 秒示例）；app_audio 优先 audio_v2、退回 exaudio；
- AUDIOPA_EN = GPIO73 由 exaudio.setup 管理。
]]

PROJECT = "music_player_ui"
VERSION = "1.0.0"

local sys = require "sys"

local theme = require "theme"
local mock  = require "mock"
local page  = require "page_music"
local ok_audio, app_audio = pcall(require, "app_audio")
if not ok_audio then app_audio = nil end

local SCREEN_W, SCREEN_H = 1024, 600

-- ═══ 内部硬件看门狗（参考 docs.openluat.com osapi/core/wdt）═══
-- Air8603（Air1603 内核）内部硬狗由固件自动开启，默认 20s 且不能关闭；
-- wdt.init(60000) 把超时放宽到本系列最大 60s，容忍偶发卡顿减少误复位。
-- 心跳 task 每秒喂一次；主循环卡死就停止喂狗，60s 后整机复位自恢复。
pcall(function()
    if wdt and type(wdt.init) == "function" then
        if wdt.init(60000) then
            log.info("wdt", "内部硬件看门狗已开启，超时 60s")
        else
            log.warn("wdt", "wdt.init 返回 false，沿用内核默认 20s")
        end
    else
        log.warn("wdt", "固件未提供 wdt 库，跳过设置（内核默认硬狗仍在）")
    end
end)

-- ═══ 板载 Air153D 外置硬件看门狗（参考 TMR_Batching_System）═══
-- 该芯片上电即计时，STRAP 选 10 分钟/60 分钟/12 小时/24 小时。
-- 不喂狗会拉 PWR_OFF → RESET_N，造成约 10 多分钟一次的整机周期复位。
-- 上面的内部 wdt 喂不到这颗外部芯片，必须单独喂。
local EXT_WDT_ENABLE = true
local EXT_WDT_PIN    = 57
if EXT_WDT_ENABLE then
    local function load_exair153x_wdt()
        return require "exair153x_wdt"
    end
    local ok, ext_wdt = pcall(load_exair153x_wdt)
    if ok and type(ext_wdt) == "table" then
        -- init 内部会 sys.taskInit 独立自动喂狗任务：首次立即喂，之后默认每 180s 一次
        if not ext_wdt.init({ wdt_pin = EXT_WDT_PIN }) then
            log.error("main", "Air153D 外置看门狗初始化失败")
        end
    else
        log.error("main", "exair153x_wdt 未打包进固件，Air153D 将周期复位整机")
    end
else
    log.warn("main", "外置看门狗已禁用，Air153D 会周期复位整机")
end

-- 内部狗心跳：每秒喂一次，同时打断点便于串口判断时基是否还在走
sys.taskInit(function()
    local beat = 0
    while true do
        sys.wait(1000)
        beat = beat + 1
        if beat % 5 == 0 then log.info("main", "tick", beat) end
        pcall(function()
            if wdt and type(wdt.feed) == "function" then wdt.feed() end
        end)
    end
end)

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
    pcall(gpio.setup, 73, 0)   -- AUDIOPA_EN 先关断，交给 exaudio.setup 接管

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
    local pok, pret = pcall(pwm.open, 3, 1000, 85)
    if not pok or pret == false then
        pcall(pwm.setup, 3, 1000, 85)
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

    -- 8. 音频后端（内置 6 秒 MP3；缺库或文件时不阻塞 UI）
    if app_audio then
        local aok, aerr = pcall(app_audio.init)
        if not aok then log.warn("main", "audio init error", aerr) end
    end

    pcall(function() math.randomseed(os.time() or 12345) end)
    ok, err = pcall(page.open)
    if not ok then
        log.error("main", "open page failed", err, debug.traceback())
    end
    log.info("main", "boot done")
end)

sys.run()
