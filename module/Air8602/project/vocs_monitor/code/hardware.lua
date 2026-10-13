--[[
@module  hardware
@summary 硬件初始化（GPIO 上电时序 + LCD + AirUI + 背光 + 触摸 + 密度缩放）
@version 1.0.0
@date    2026.10.10
@usage
require "hardware" 后：
  hardware.init_density_scale()  -- 设置屏幕密度缩放（需在 require 界面模块前调用）
  hardware.init()                -- 上电 + LCD + AirUI + 背光 + 触摸（需在 task 中调用）
]]

local M = {}
local config = require "config"
local lcd_hx8282 = require "lcd_hx8282_10in"
local tp_gt911 = require "tp_gt911"

-- 以 1024x600 为设计基准，计算密度缩放系数（其它分辨率可整体等比缩放）
function M.init_density_scale()
    _G.density_scale = 1
    local ok, w, h = pcall(function() return display.getSize() end)
    if ok and type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
        _G.density_scale = math.min(w / config.lcd.w, h / config.lcd.h)
    end
    log.info("hardware", "屏幕密度缩放系数", _G.density_scale)
end

-- 上电时序：各 GPIO 电平切换之间按配置延时，确保电源/复位稳定
local function power_on()
    if not gpio or not gpio.setup then
        log.warn("hardware", "无 gpio 库（PC 模拟器），跳过上电时序")
        return
    end
    for _, s in ipairs(config.power_steps) do
        gpio.setup(s.pin, 0)
        gpio.set(s.pin, s.level)
        if s.delay then
            sys.wait(s.delay)
        end
    end
    log.info("hardware", "GPIO 上电完成")
end

-- 屏幕：LCD -> AirUI -> 背光
local function init_screen()
    -- PC 模拟器无 display 库，直接走 AirUI（SDL 窗口）
    if display and display.init then
        local lcd_ok = lcd_hx8282.init(config.lcd)
        log.info("hardware", "display.init", lcd_ok)
        if not lcd_ok then
            -- 真机 LCD 失败通常意味着硬件异常；模拟器则可能无 display 驱动，
            -- 这里只告警不中断，继续尝试 AirUI（AirUI 自带显示后端）
            log.warn("hardware", "LCD 初始化失败，继续尝试 AirUI")
        end
    else
        log.warn("hardware", "无 display 库（PC 模拟器），跳过 LCD 初始化")
    end

    if not airui or not airui.init then
        log.error("hardware", "airui 库不存在，无法初始化界面（需 GUI 版固件）")
        return false
    end

    local w, h = config.lcd.w, config.lcd.h
    if display and display.getSize then
        local ok, dw, dh = pcall(display.getSize)
        if ok and type(dw) == "number" and dw > 0 then
            w, h = dw, dh
        end
    end

    local airui_ok = airui.init(w, h)
    log.info("hardware", "airui.init", airui_ok, w, h)
    if not airui_ok then
        return false
    end

    -- hzfont 在部分固件/模拟器上不可用，加载失败不应阻断启动
    local font_ok = pcall(airui.font_load,
        { type = "hzfont", size = config.font_size, cache_size = 1024, antialias = 1 })
    if not font_ok then
        log.warn("hardware", "hzfont 加载失败，回退默认字体")
    end
    airui.set_rotation(0)

    if gpio and gpio.setup then
        gpio.setup(config.backlight_pin, 0)
        gpio.set(config.backlight_pin, 1)
        log.info("hardware", "背光已开启")
    end
    return true
end

-- 触摸：GT911 -> 绑定 AirUI
local function init_touch()
    local tp_ok = tp_gt911.init({
        port = config.touch.port,
        pin_rst = config.touch.pin_rst,
        pin_int = config.touch.pin_int,
        int_type = (tp and tp.FALLING) or 1,
        w = config.touch.w,
        h = config.touch.h,
    })
    log.info("hardware", "tp.init", tp_ok)
    return tp_ok
end

function M.init()
    power_on()
    if not init_screen() then
        return false
    end
    init_touch()
    return true
end

return M
