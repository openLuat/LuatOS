--[[
@module hardware
@summary 硬件初始化模块（GPIO 上电、LCD、触摸、密度缩放）
@version 2.0
@date 2026.10.23
@author 王城钧
@usage
require "hardware" 后：
hardware.init_density_scale()  -- 设置屏幕密度缩放（需在 require 界面模块前调用）
hardware.init()                -- 上电 + LCD + AirUI + 背光 + 触摸（需在 task 中调用）
@note 支持两种板级，由 M.profile 选择：
      "air8607_10i" Air8607(Air1603) + 官方 AirLCD_1100 10.1寸（JD9165BA，1024x600 RGB，
                    GT911 触摸，PWM3 背光）——默认，依据 eng_8607_10i_v0.lua；
      "air8601_7i"  Air8601(Air1601) + 7寸 HX8282（1024x600 RGB，GT911，PIN43/GPIO13 背光）。
      两种屏同为 1024x600，界面布局与密度基准不变。
]]
local M = {}

M.profile = "air8607_10i"

local tp_gt911 = require "tp_gt911"

local function is_pc()
    return rtos and rtos.bsp and rtos.bsp() == "PC"
end

-- 初始化屏幕密度缩放系数（以 1024x600 为设计基准）
function M.init_density_scale()
    _G.density_scale = 1
    local ok, w, h = pcall(function() return display.getSize() end)
    if ok and type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
        local scale_w = w / 1024
        local scale_h = h / 600
        _G.density_scale = math.min(scale_w, scale_h)
    end
    log.info("hardware", "屏幕密度缩放系数", _G.density_scale)
end

-- ===== Air8601：硬件上电时序（参照 Air1601 EVB 板 power_on）=====
local function power_on_8601()
    local steps = {
        { pin = 42, level = 1, delay = 50 },
        { pin = 65, level = 0, delay = 100 },
        { pin = 65, level = 1, delay = 1000 },
        { pin = 43, level = 1 }, -- ★ 背光驱动脚（PIN43，需先在 lcd_hx8282_10in 里 pins.setup(43,"GPIO13") 复用才会生效）
        { pin = 52, level = 1 },
        { pin = 56, level = 1 },
        { pin = 73, level = 1, delay = 200 }, -- UVC 摄像头使能（AirCAMERA_1034），延时 200ms
    }

    for _, s in ipairs(steps) do
        gpio.setup(s.pin, 0)
        gpio.set(s.pin, s.level)
        if s.delay then
            sys.wait(s.delay)
        end
    end

    log.info("hardware", "GPIO 上电完成（Air8601）")
end

-- ===== Air8607：官方 factory 的 pins 段为空，使用默认复用 =====
-- SD_EN = GPIO74 拉高；AUDIOPA_EN = GPIO73 拉低关断未使用功放；
-- 背光 PWM3（PIN55/GPIO13）先以 0 占空比启动，首帧后点亮。
-- 不引用 Air8601 的 PIN43/PIN32/PIN33，也不预置 GPIO38（I2C1 SDA 交给 i2c 接管）。
local function power_on_8607()
    gpio.setup(74, 0)
    gpio.set(74, 1)
    gpio.setup(73, 0)
    gpio.set(73, 0)
    if pwm and pwm.setup and pwm.start then
        pwm.setup(3, 1000, 0)
        pwm.start(3)
    end
    log.info("hardware", "GPIO 上电完成（Air8607）")
end

-- AirUI 初始化（两种板级共用）
local function init_airui(w, h)
    local airui_ok = airui.init(w, h)
    log.info("hardware", "airui.init", airui_ok, w, h)
    if not airui_ok then
        return false
    end

    -- 加载合宙内置矢量字库 hzfont（支持 12-255 号中文）
    airui.font_load({
        type       = "hzfont",
        size       = 20,
        cache_size = 2048,
        antialias  = 1
    })
    airui.set_rotation(0)
    return true
end

-- ===== Air8601：HX8282 屏幕初始化（LCD → AirUI → 背光）=====
local function init_screen_8601()
    -- 只在 8601 板级 require：该文件顶层会执行 pins.setup(43,"GPIO13")，8607 上不能执行
    local lcd_hx8282 = require "lcd_hx8282_10in"
    local lcd_ok = lcd_hx8282.init({
        interface  = "rgb",
        pin_rst    = 15,
        direction  = 0,
        w          = 1024,
        h          = 600,
        hbp        = 140,
        hspw       = 20,
        hfp        = 160,
        vbp        = 20,
        vspw       = 3,
        vfp        = 12,
        bus_speed  = 50 * 1000 * 1000,
    })
    log.info("hardware", "display.init", lcd_ok)
    if not lcd_ok then
        return false
    end

    -- FrameBuffer 由 display.init 内部完成分配，无需 lcd.setupBuff / lcd.autoFlush
    local w, h = display.getSize()
    if not init_airui(w, h) then
        return false
    end

    -- 背光脚是 PIN43/GPIO13：由 lcd_hx8282_10in.lua 的 pins.setup(43,"GPIO13") 复用，
    -- 并在 hardware.power_on 的 { pin = 43, level = 1 } 里点亮。
    -- GPIO38 是 I2C1 的 SDA（GT911 触摸屏总线），不是背光脚。
    gpio.setup(38, 0)
    gpio.set(38, 1)

    log.info("hardware", "屏幕初始化完成（Air8601，背光已在 power_on 中点亮）")
    return true
end

-- ===== Air8607：JD9165BA 屏幕初始化（官方扩展库 → AirUI）=====
local function init_screen_8607()
    -- JD9165BA 为免初始化 IC：无 SPI 引脚、无寄存器序列，只做复位 + RGB 时序配置
    local ok, info = require("exd_jd9165ba_rgb").setup({
        pin_rst     = 15,
        screen_size = 10.1,
        w           = 1024,
        h           = 600,
        rotation    = 0,
        hbp         = 140,
        hspw        = 20,
        hfp         = 160,
        vbp         = 20,
        vspw        = 3,
        vfp         = 12,
        bus_speed   = 50 * 1000 * 1000,
    })
    log.info("hardware", "JD9165BA display.init", ok, type(info) == "table" and info.backend or info)
    if not ok then
        return false
    end

    -- 后端可能为 display（优先）或 lcd（降级），优先以实际后端尺寸为准
    local w, h = info.w, info.h
    local backend = (info.backend == "display") and display or lcd
    if backend and backend.getSize then
        local ok2, gw, gh = pcall(backend.getSize)
        if ok2 and gw and gh then w, h = gw, gh end
    end
    log.info("hardware", "屏幕尺寸", w, h)
    if not init_airui(w, h) then
        return false
    end

    log.info("hardware", "屏幕初始化完成（Air8607，背光由 PWM3 控制）")
    return true
end

-- 触摸初始化（GT911 → 绑定 AirUI）
local function init_touch()
    local params = { port = 1, int_type = tp.FALLING, w = 1024, h = 600 }
    if M.profile == "air8607_10i" then
        -- 官方 tp_gt911：I2C1 轮询模式，TP_RST=GPIO14，TP_INT=GPIO51
        i2c.setup(1, 0, true)
        params.pin_rst = 14
        params.pin_int = 51
    else
        params.pin_rst = 56
        params.pin_int = 51
    end
    local tp_ok = tp_gt911.init(params)
    log.info("hardware", "tp.init", tp_ok)
    return tp_ok
end

-- 背光点亮（仅 Air8607 的 PWM3 需要；Air8601 在 power_on 中已点亮 PIN43）
function M.backlight_on()
    if is_pc() then return end
    if M.profile == "air8607_10i" and pwm and pwm.setDuty then
        pwm.setDuty(3, 90)
    end
end

-- 硬件总初始化（上电 → 屏幕 → 触摸）
function M.init()
    local pc = is_pc()
    if not pc then
        if M.profile == "air8607_10i" then
            if not (gpio and i2c and tp) then
                log.error("hardware", "固件缺少 GPIO/I2C/TP 核心库")
                return false
            end
            power_on_8607()
        else
            if not (pins and gpio and i2c and tp) then
                log.error("hardware", "固件缺少 PINS/GPIO/I2C/TP 核心库")
                return false
            end
            power_on_8601()
        end
    end

    local screen_ok
    if pc then
        screen_ok = init_airui(1024, 600)
    elseif M.profile == "air8607_10i" then
        screen_ok = init_screen_8607()
    else
        screen_ok = init_screen_8601()
    end
    if not screen_ok then
        return false
    end

    if not pc then
        init_touch()
        -- 8607 背光走 PWM：即使上层忘记调用 backlight_on，也兜底在首帧后点亮
        if M.profile == "air8607_10i" then
            sys.timerStart(function() M.backlight_on() end, 500)
        end
    end
    return true
end

return M
