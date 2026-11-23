--[[
@module  hardware
@summary 硬件初始化（Air8607/Air1603 + 官方 AirLCD_1100 10.1 寸 1024x600）
@version 1.0.0
@usage require "hardware" 后：
      hardware.init_density_scale()  -- 需在 require 界面模块前调用
      hardware.init()                -- 上电 + 屏幕 + AirUI + 触摸（在 task 中调用）
@note 屏幕：JD9165BA（免初始化 IC，只做复位 + RGB 时序）；触摸：GT911（I2C1 轮询，
      TP_RST=GPIO14 / TP_INT=GPIO51）；背光：PWM3（首帧后点亮）。
]]
local M = {}

local tp_gt911 = require "tp_gt911"

local function is_pc()
    return rtos and rtos.bsp and rtos.bsp() == "PC"
end

-- 以 1024x600 为设计基准
function M.init_density_scale()
    _G.density_scale = 1
    local ok, w, h = pcall(function() return display.getSize() end)
    if ok and type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
        _G.density_scale = math.min(w / 1024, h / 600)
    end
    log.info("hardware", "屏幕密度缩放系数", _G.density_scale)
end

-- SD_EN=GPIO74 拉高；AUDIOPA_EN=GPIO73 拉低；背光 PWM3 先 0 占空比
local function power_on()
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

local function init_airui(w, h)
    local ok = airui.init(w, h)
    log.info("hardware", "airui.init", ok, w, h)
    if not ok then return false end
    -- 合宙内置矢量字库：12-255 号中文（本工程最小 16 号）
    airui.font_load({ type = "hzfont", size = 20, cache_size = 2048, antialias = 1 })
    airui.set_rotation(0)
    return true
end

local function init_screen()
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
    if not ok then return false end
    local w, h = info.w, info.h
    local backend = (info.backend == "display") and display or lcd
    if backend and backend.getSize then
        local ok2, gw, gh = pcall(backend.getSize)
        if ok2 and gw and gh then w, h = gw, gh end
    end
    return init_airui(w, h)
end

local function init_touch()
    i2c.setup(1, 0, true)
    local ok = tp_gt911.init({ port = 1, int_type = tp.FALLING, w = 1024, h = 600,
        pin_rst = 14, pin_int = 51 })
    log.info("hardware", "tp.init", ok)
    return ok
end

-- 背光亮度（PWM3 占空比，0~100）。默认 100 = 最亮；
-- 若现场觉得夜间刺眼，改成 80 左右即可（改动只影响这里）
local BL_DUTY = 100

function M.backlight_on()
    if is_pc() then return end
    if pwm and pwm.setDuty then pwm.setDuty(3, BL_DUTY) end
end

-- 运行期调光（可选）：hardware.set_brightness(60)
function M.set_brightness(duty)
    if is_pc() then return end
    duty = math.max(0, math.min(100, math.floor(duty or 100)))
    BL_DUTY = duty
    if pwm and pwm.setDuty then pwm.setDuty(3, duty) end
    log.info("hardware", "背光亮度", duty)
end

function M.init()
    local pc = is_pc()
    if not pc then
        if not (gpio and i2c and tp) then
            log.error("hardware", "固件缺少 GPIO/I2C/TP 核心库")
            return false
        end
        power_on()
        if not init_screen() then return false end
        init_touch()
        sys.timerStart(function() M.backlight_on() end, 500)
    else
        if not init_airui(1024, 600) then return false end
    end
    log.info("hardware", "硬件初始化完成")
    return true
end

return M
