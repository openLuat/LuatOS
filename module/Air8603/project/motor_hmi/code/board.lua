--[[
@module  board
@summary Air8603W1 板级初始化：上电时序 → RGB 屏 → 背光（不再涉及 airui）
@version 2.0.0
@date    2026.11.12

与 airui 版的差别：
  plcui 自己管画布和刷新，本模块只负责「把屏点亮」和「能看见」，
  不再调用 airui.init / airui.font_load / airui.device_bind_touch。

时序要点：
1. 背光 PWM 先以 0 占空比启动，压灭背光，避免上电闪屏和热复位残影；
2. 电源域按 5V → 9V → 12V → 5VOUT → 网络模组RST → SD → 485 的顺序依次上电；
3. 显示屏依赖电源域，必须在上电完成后初始化；
4. 背光由 main.lua 在 plcui.load 成功后调用 backlight_on() 点亮。
]]
local M = {}

local conf = require "conf"
local lcd = require "drv_lcd_rgb"

local IS_PC = (rtos.bsp() == "PC")

local function pin_out(pin, level)
    pcall(gpio.setup, pin, level)
    pcall(gpio.set, pin, level)
end

--[[
上电时序：按 conf.board.power_on 表依次设置引脚电平
@return nil
]]
function M.power_on()
    if IS_PC then return end

    local bl = conf.board.backlight
    pcall(pwm.setup, bl.pwm_ch, bl.pwm_freq, 0)
    pcall(pwm.start, bl.pwm_ch)

    for _, step in ipairs(conf.board.power_on) do
        pin_out(step[1], step[2])
        if step[3] then
            sys.wait(step[3])
        end
    end
end

--[[
初始化 RGB 屏
@return boolean
]]
function M.display_on()
    return lcd.init(conf.board.lcd)
end

--[[
点亮背光（plcui.load 成功、首帧出来之后调用）
@param level number 0~100，默认取 conf.board.backlight.level
@return nil
]]
function M.backlight_on(level)
    if IS_PC then return end
    local bl = conf.board.backlight
    pcall(pwm.setup, bl.pwm_ch, bl.pwm_freq, level or bl.level)
    pcall(pwm.start, bl.pwm_ch)
end

--[[
板级初始化（上电 + 屏），不含背光
@return boolean 屏初始化是否成功
]]
function M.init()
    M.power_on()
    local ok = M.display_on()
    if not ok then
        log.error("board", "显示屏初始化失败，请检查 display 库与接线")
    end
    return ok
end

return M
