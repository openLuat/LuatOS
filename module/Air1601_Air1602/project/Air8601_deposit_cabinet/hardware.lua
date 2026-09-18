--[[
@module  hardware
@summary 硬件初始化模块（GPIO 上电、LCD、触摸、密度缩放）
@version 1.0
@date    2026.08.13
@author  王城钧
@usage
require "hardware" 后：
  hardware.init_density_scale()  -- 设置屏幕密度缩放（需在 require 界面模块前调用）
  hardware.init()                -- 上电 + LCD + AirUI + 背光 + 触摸（需在 task 中调用）
]]

local M = {}

local lcd_hx8282 = require "lcd_hx8282_10in"
local tp_gt911 = require "tp_gt911"

-- 初始化屏幕密度缩放系数（以 1024x600 为设计基准）
function M.init_density_scale()
    _G.density_scale = 1
    local ok, w, h = pcall(lcd.getSize)
    if ok and type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
        local scale_w = w / 1024
        local scale_h = h / 600
        _G.density_scale = math.min(scale_w, scale_h)
    end
    log.info("hardware", "屏幕密度缩放系数", _G.density_scale)
end

-- 硬件上电时序（参照 Air1601 EVB 板 power_on）
local function power_on()
    local steps = {
        { pin = 42, level = 1, delay = 50 },
        { pin = 65, level = 0, delay = 100 },
        { pin = 65, level = 1, delay = 1000 },
        { pin = 43, level = 1 }, -- ★ 背光驱动脚（PIN43，需先在 lcd_hx8282_10in 里 pins.setup(43,"GPIO13") 复用才会生效）
        { pin = 52, level = 1 },
        { pin = 56, level = 1 },
        -- { pin = 57, level = 1 },
        { pin = 73, level = 1, delay = 200 }, -- UVC 摄像头使能（AirCAMERA_1034），延时等待摄像头就绪后再初始化 LCD
    }
    for _, s in ipairs(steps) do
        gpio.setup(s.pin, 0)
        gpio.set(s.pin, s.level)
        if s.delay then
            sys.wait(s.delay)
        end
    end
    log.info("hardware", "GPIO 上电完成")
end

-- 屏幕初始化（LCD → AirUI → 背光）
local function init_screen()
    local lcd_ok = lcd_hx8282.init({
        port = lcd.RGB,
        pin_rst = 15,
        pin_de = 25,
        -- pin_pwr = 57,
        direction = 0,
        w = 1024,
        h = 600,
        hbp = 140,
        hspw = 20,
        hfp = 160,
        vbp = 20,
        vspw = 3,
        vfp = 12,
        bus_speed = 50 * 1000 * 1000,
    })
    log.info("hardware", "lcd.init", lcd_ok)
    if not lcd_ok then
        return false
    end

    lcd.setupBuff(nil, true)
    lcd.autoFlush(false)

    local w, h = lcd.getSize()
    local airui_ok = airui.init(w, h)
    log.info("hardware", "airui.init", airui_ok, w, h)
    if not airui_ok then
        return false
    end

    airui.font_load({ type = "hzfont", size = 20, cache_size = 1024, antialias = 1 })
    airui.set_rotation(0)

    -- 这里的 GPIO38 不是背光！Air8601 的真实背光脚是 PIN43/GPIO13（见 lcd_hx8282_10in.lua 的
    -- pins.setup(43,"GPIO13") + power_on 里的 { pin = 43, level = 1 }）。
    -- GPIO38 是 I2C1 的 SDA，本句在 i2c.setup 之前执行所以暂时无害，但已无实际作用。
    gpio.setup(38, 0)
    gpio.set(38, 1)
    log.info("hardware", "背光已开启")

    return true
end

-- 触摸初始化（GT911 → 绑定 AirUI）
local function init_touch()
    local tp_ok = tp_gt911.init({
        port = 1,
        pin_rst = 72,
        pin_int = 51,
        int_type = tp.FALLING,
        w = 1024,
        h = 600,
    })
    log.info("hardware", "tp.init", tp_ok)
    return tp_ok
end

-- 硬件总初始化（上电 → 屏幕 → 触摸）
function M.init()
    power_on()
    if not init_screen() then
        return false
    end
    init_touch()
    return true
end

return M
