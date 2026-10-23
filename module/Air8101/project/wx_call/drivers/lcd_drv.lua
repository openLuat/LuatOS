--[[
@module  lcd_drv
@summary LCD 上电时序 + 驱动 + AirUI 初始化（lcd / pins / pwm / gpio / airui 核心库）
@version 1.2.0
@date    2026.10.21
@usage
  local lcd_drv = require "lcd_drv"
  lcd_drv.init()            -- 必须在协程里调用（内有 sys.wait 上电延时）
  lcd_drv.backlight_on()
]]

local cfg = require "hw_config"

local M = {}

local c = cfg.lcd

-- 默认逻辑分辨率（lcd.getSize() 成功后会被覆盖）
UI_W, UI_H = c.params.w, c.params.h

-- 引脚复用
local function apply_pins()
    if not pins then
        log.warn("lcd_drv", "pins 库不可用，跳过引脚复用（触摸将走软件 I2C 回退）")
        return
    end
    for _, p in ipairs(cfg.pins or {}) do
        pcall(pins.setup, p.pin, p.func)
    end
end

-- 外设上电时序（含延时，必须在协程中调用）
local function power_on()
    for _, s in ipairs(cfg.power_on or {}) do
        if s.pull then
            pcall(gpio.setup, s.pin, s.dir, s.pull)
        else
            pcall(gpio.setup, s.pin, s.dir)
        end
        if s.dir == 0 and s.level ~= nil then
            pcall(gpio.set, s.pin, s.level)
        end
        if s.delay then
            sys.wait(s.delay)
        end
    end
end

--- 打开背光：GPIO 使能 + PWM 调光（固件无 pwm 时自动跳过调光）
function M.backlight_on()
    local bl = c.backlight or {}

    if bl.gpio then
        pcall(gpio.setup, bl.gpio, 0)
        pcall(gpio.set, bl.gpio, 1)
    end

    if bl.pwm_ch and pwm and pwm.setup then
        local ok = pcall(pwm.setup, bl.pwm_ch, bl.pwm_freq or 10000, 100)
        if ok then
            pcall(pwm.start, bl.pwm_ch)
        else
            log.warn("lcd_drv", "PWM 背光初始化失败，仅用 GPIO 使能")
        end
    end

    log.info("lcd_drv", "backlight on")
end

--- 初始化 LCD + AirUI + 字体
-- @return boolean
function M.init()
    apply_pins()
    power_on()

    local ok = lcd.init(c.model, c.params)
    if not ok then
        -- 兼容不同固件：去掉 xoffset/yoffset 等非必需参数重试一次
        log.warn("lcd_drv", "lcd.init 首次失败，使用精简参数重试")
        ok = lcd.init(c.model, {
            port      = c.params.port,
            pin_rst   = c.params.pin_rst,
            direction = c.params.direction,
            w         = c.params.w,
            h         = c.params.h,
        })
    end
    if not ok then
        log.error("lcd_drv", "lcd.init fail", c.model)
        return false
    end

    local w, h = lcd.getSize()
    if type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
        UI_W, UI_H = w, h
    end

    -- 显式指定 RGB565，避免部分固件默认格式不一致导致花屏
    local ok_ui
    if airui.COLOR_FORMAT_RGB565 then
        ok_ui = airui.init(UI_W, UI_H, airui.COLOR_FORMAT_RGB565)
    else
        ok_ui = airui.init(UI_W, UI_H)
    end
    if not ok_ui then
        log.error("lcd_drv", "airui.init fail")
        return false
    end

    if c.need_buffer then
        if not lcd.setupBuff(nil, true) then
            log.error("lcd_drv", "帧缓冲分配失败，可能内存不足")
        end
        lcd.autoFlush(false)          -- 关闭自动刷屏，由 airui 控制刷新时机
    end

    -- 中文字体：先试文件系统根目录，再试脚本区 /luadb 同名文件
    -- 注意：font_load 失败返回 false/nil，成功返回字体对象，必须用 truthy 判断
    local f = cfg.font or {}
    local tries = { f.path, "/luadb" .. (f.path or "") }
    local loaded = false
    for _, p in ipairs(tries) do
        if p and #p > 0 then
            local okf, ret = pcall(airui.font_load, {
                type       = "hzfont",
                path       = p,
                size       = f.size or 20,
                cache_size = f.cache_size or 1024,
                antialias  = f.antialias or 1,
                global     = true,
            })
            if okf and ret then
                loaded = true
                log.info("lcd_drv", "font loaded", p)
                break
            end
            log.warn("lcd_drv", "font_load 失败", p, tostring(ret))
        end
    end
    if not loaded then
        log.error("lcd_drv", "中文字体加载失败，界面会显示方框：请确认文件系统或 /luadb 下有 MiSans_gb2312.ttf")
    end

    local vok, ver = pcall(airui.version)
    log.info("lcd_drv", "screen", UI_W, UI_H, "airui", vok and ver or "unknown")
    return true
end

return M
