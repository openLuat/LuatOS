--[[
@module  lcd_drv
@summary LCD驱动初始化模块（支持多硬件环境，通过 HARDWARE_ENV 切换）
@version 1.1.0
@date    2026.10.16
@author  拓毅恒
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕（支持多种硬件环境）；
2、配置LCD显示参数；
3、初始化AirUI；
4、开启背光（GPIO直拉 / PWM调光）；

支持硬件环境（修改文件顶部 HARDWARE_ENV 切换）：
  "EK79001_5INCH"  - 5寸RGB屏(EK79001 IC)，pin_rst=22，背光GPIO8
  "AIR8607_10INCH" - 合宙引擎Air8607 10寸RGB屏，pin_rst=15，背光PWM3(GPIO13)

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
2、lcd_drv.get_size()：查询屏幕尺寸
]]

-- ============ 硬件环境配置（按实际板子修改 HARDWARE_ENV） ============
--   "EK79001_5INCH"  → 原5寸RGB屏，EK79001 IC，pin_rst=22，背光GPIO8
--   "AIR8607_10INCH" → 合宙引擎Air8607 10寸RGB屏，pin_rst=15，背光PWM3(GPIO13)
HARDWARE_ENV = "EK79001_5INCH"   -- 默认Air8607；使用原5寸屏请改为"EK79001_5INCH"

-- 各硬件环境的 LCD 参数（驱动/复位脚/分辨率/时序/背光）
local lcd_hw = {
    EK79001_5INCH = {
        driver      = "exd",                 -- 走 exd_ek79001_rgb.setup
        pin_rst     = 22,                    -- 原5寸屏复位脚
        screen_size = 5.0,
        backlight   = { gpio_bl = 8 },       -- 背光 GPIO8 直接拉高
    },
    AIR8607_10INCH = {
        driver      = "rgb",                 -- 走 lcd_display_rgb (display.init)
        pin_rst     = 15,                    -- LCD_DISP = GPIO15
        w = 1024, h = 600,                   -- 10寸 RGB 分辨率
        hbp = 140, hspw = 20, hfp = 160,     -- RGB 时序（1024x600 生态实测组）
        vbp = 20,  vspw = 3,  vfp = 12,
        bus_speed = 50 * 1000 * 1000,        -- RGB 总线时钟 50MHz
        screen_size = 10.0,
        backlight   = { pwm_ch = 3, pwm_freq = 1000, level = 100 }, -- PWM3(GPIO13)
    },
}

local cfg = lcd_hw[HARDWARE_ENV] or lcd_hw.AIR8607_10INCH

-- PWM 背光上电占空比 0，界面就绪前保持熄灭
if cfg.backlight and cfg.backlight.pwm_ch then
    pwm.setup(cfg.backlight.pwm_ch, cfg.backlight.pwm_freq or 1000, 0)
    pwm.start(cfg.backlight.pwm_ch)
    log.info("lcd_drv", "背光上电占空比0 PWM ch=" .. cfg.backlight.pwm_ch)
end

local lcd_width, lcd_height = cfg.w or 1024, cfg.h or 600

-- 开启背光：PWM 调光 或 GPIO 直拉
local function lcd_backlight_on(bl)
    if not bl then return end
    if bl.pwm_ch then
        -- PWM 背光：先拉使能脚（若有 gpio_bl）再启动 PWM
        if bl.gpio_bl then
            gpio.setup(bl.gpio_bl, 1)
            gpio.set(bl.gpio_bl, 1)
        end
        local ch   = bl.pwm_ch
        local freq = bl.pwm_freq or 1000
        local duty = bl.level or 100
        pwm.setup(ch, freq, duty)   -- 配置并缓存，不输出
        pwm.start(ch)               -- 启动 PWM 输出
        log.info("lcd_drv", "背光开启 PWM ch=" .. ch .. " freq=" .. freq .. " duty=" .. duty)
    elseif bl.gpio_bl then
        gpio.setup(bl.gpio_bl, 1)
        gpio.set(bl.gpio_bl, 1)
        log.info("lcd_drv", "背光开启 GPIO=" .. bl.gpio_bl)
    end
end

local function lcd_drv_init()
    if cfg.driver == "exd" then
        -- ===== 原5寸 EK79001 RGB 屏（exd_ek79001_rgb） =====
        local exd = require "exd_ek79001_rgb"
        local ok, info = exd.setup({
            pin_rst     = cfg.pin_rst,
            screen_size = cfg.screen_size,
        })
        log.info("lcd_drv", "exd.setup", ok)
        if not ok or not info then return false end
        lcd_width, lcd_height = info.w, info.h
    else
        -- ===== 合宙引擎 Air8607 10寸 RGB 屏（lcd_display_rgb / display.init） =====
        local lcd_display_rgb = require "lcd_display_rgb"
        local ok = lcd_display_rgb.init({
            interface = "rgb",
            pin_rst   = cfg.pin_rst,
            w  = cfg.w,  h  = cfg.h,
            hbp = cfg.hbp, hspw = cfg.hspw, hfp = cfg.hfp,
            vbp = cfg.vbp, vspw = cfg.vspw, vfp = cfg.vfp,
            bus_speed = cfg.bus_speed,
        })
        log.info("lcd_drv", "lcd_display_rgb.init", ok)
        if not ok then return false end
        -- 取真实分辨率（display.init 已注册 FB）
        if display and display.getSize then
            local dw, dh = display.getSize()
            if dw and dw > 0 then lcd_width, lcd_height = dw, dh end
        end
    end

    -- 初始化 AirUI
    local airui_result = airui.init(lcd_width, lcd_height)
    if not airui_result then
        log.error("airui", "init failed")
        return false
    end
    log.info("airui", "init success", lcd_width, lcd_height)

    -- 开启背光
    lcd_backlight_on(cfg.backlight)

    return true
end

-- 查询屏幕尺寸
local function lcd_drv_get_size()
    return lcd_width, lcd_height
end

-- 导出接口
lcd_drv = {
    init = lcd_drv_init,
    get_size = lcd_drv_get_size,
}
