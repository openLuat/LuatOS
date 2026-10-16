--[[
@module  main
@summary MJPG 视频播放测试（display 库 + AirUI），支持多硬件环境
@version 1.1
@date    2026.10.16
@usage
播放 /luadb/fly_man_80.mjpg，用 display 库初始化 RGB 屏，再交给 AirUI 的 airui.video
组件显示，居中 + 循环播放。

支持硬件环境（修改文件顶部 HARDWARE_ENV 切换）：
  "EVB_AIR1601_7INCH" - 原 EVB_Air1601 7寸屏(HX8282)，pin_rst=15，pin_pwr=2(GPIO2 背光+供电)
  "AIR8607_10INCH"    - 合宙引擎 Air8607 10寸屏，pin_rst=15，背光 PWM3(GPIO13)
  （Air8607 参数参考 factory 工程的 config/eng_8607_10i_v0.lua）
]]

PROJECT = "play_mjpg_display"
VERSION = "1.0.0"

-- ============ 硬件环境配置（按实际板子修改 HARDWARE_ENV） ============
--   "EVB_AIR1601_7INCH" → EVB_Air1601 7寸屏(HX8282)，pin_rst=15，pin_pwr=2(GPIO2 背光+供电)
--   "AIR8607_10INCH"    → 合宙引擎 Air8607 10寸屏，pin_rst=15，背光 PWM3(GPIO13)
HARDWARE_ENV = "EVB_AIR1601_7INCH"   -- 默认EVB_Air1601；使用Air8607的10寸EVB请改为"AIR8607_10INCH"

-- 各硬件环境的 LCD 参数
local lcd_hw = {
    EVB_AIR1601_7INCH = {
        w = 1024, h = 600,
        pin_rst = 15,
        pin_pwr = 2,        -- GPIO2 同时控制背光+供电（display.init 通过 pin_pwr 点亮）
        backlight = nil,    -- 背光由 display.init(pin_pwr) 点亮，无需额外处理
    },
    AIR8607_10INCH = {
        w = 1024, h = 600,
        pin_rst = 15,       -- LCD_DISP = GPIO15
        pin_pwr = nil,      -- Air8607 屏无需 SPI/供电脚，背光走 PWM3
        backlight = { pwm_ch = 3, pwm_freq = 1000, level = 100 }, -- PWM3=GPIO13
    },
}
local cfg = lcd_hw[HARDWARE_ENV] or lcd_hw.AIR8607_10INCH
local LCD_W, LCD_H = cfg.w, cfg.h

-- 视频文件路径（放 luadb 分区）
local VIDEO = "/luadb/fly_man_80.mjpg"

sys.taskInit(function()
    -- ===== 1. 用 display 库初始化 RGB 屏 =====
    -- 注意：AirUI 通过 luat_display_get_by_id(0) 取默认屏，这里必须显式 id=0
    local ok, err = display.init("custom", {
        id        = 0,
        interface = "rgb",
        w         = LCD_W,
        h         = LCD_H,
        -- RGB 时序
        hbp  = 140, hspw = 20, hfp = 160,
        vbp  = 20,  vspw = 3,  vfp = 12,
        pclk_hz = 50 * 1000 * 1000,
        pin_rst = cfg.pin_rst,
        pin_pwr = cfg.pin_pwr,   -- Air8607 为 nil，display.init 不驱动供电脚
    })
    if not ok then
        log.error("main", "display.init fail", err)
        return
    end
    log.info("main", "display.init ok")

    -- ===== 1.1 背光开启（Air8607 走 PWM3；EVB 已由 pin_pwr 点亮，无需处理）=====
    if cfg.backlight and cfg.backlight.pwm_ch then
        local bl = cfg.backlight
        pwm.setup(bl.pwm_ch, bl.pwm_freq or 1000, bl.level or 100)
        pwm.start(bl.pwm_ch)
        log.info("main", "背光开启 PWM ch=" .. bl.pwm_ch .. " freq=" .. (bl.pwm_freq or 1000) .. " duty=" .. (bl.level or 100))
    end

    -- ===== 2. 读视频真实分辨率，用于居中 =====
    local vw, vh = 160, 160
    local p = videoplayer.open(VIDEO)
    if p then
        local info = videoplayer.info(p)
        if info then vw, vh = info.width, info.height end
        videoplayer.close(p)
    else
        log.warn("main", "can't open video, use 160x160")
    end
    local vx = math.max(0, math.floor((LCD_W - vw) / 2))
    local vy = math.max(0, math.floor((LCD_H - vh) / 2))

    -- ===== 3. 初始化 AirUI（全局可用，late-load，不需 require）=====
    if not airui.init(LCD_W, LCD_H) then
        log.error("main", "airui.init fail")
        return
    end
    log.info("main", "airui.init ok", LCD_W, LCD_H)

    -- ===== 4. 全屏黑色背景 + 居中视频组件 =====
    local bg = airui.container({ x = 0, y = 0, w = LCD_W, h = LCD_H, color = 0x000000 })
    local v = airui.video({
        parent = bg,
        x = vx, y = vy, w = vw, h = vh,
        src = VIDEO,
        format = "mjpg",
        decode_mode = "hw",   -- 硬件解码（CCM42xx imagedecoder）
        interval = 66,        -- 约15fps
        loop = true,          -- 循环播放
        auto_play = true,     -- 创建即播放
    })
    if not v then
        log.error("main", "airui.video create fail")
        return
    end

    log.info("main", "video playing", vw, "x", vh, "at", vx, vy)

    while true do
        sys.wait(1000)
        log.info("main", "mem", rtos.meminfo("sys"))
    end
end)

sys.run()
