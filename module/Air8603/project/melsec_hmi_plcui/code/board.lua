--[[
@module  board
@summary Air8603W1 板级初始化：上电时序 → RGB 屏 → 触摸（plcui 由 ui_hmi 负责）
@version 1.0.0
@date    2026.11.11

时序要点：
1. 背光 PWM 先以 0 占空比启动，压灭背光，避免上电闪屏和热复位残影；
2. 电源域按 5V → 9V → 12V → 5VOUT → 网络模组RST → SD → 485 的顺序依次上电，每步留延时；
3. 显示屏和触摸都依赖电源域，必须在上电完成后初始化；
4. 背光由 main.lua 在首屏绘制完成后调用 backlight_on() 点亮。

与 melsec_hmi（airui 版）的差别：
  airui.init 会自己 mipi/rgb_init 并建屏，plcui 也在 init 时接管 display 0，
  两者只能二选一。所以这里只做"上电 + display 初始化"，
  界面初始化交给 ui_hmi.init()，触摸绑定放在它之后（见 main.lua 的顺序）。
]]
local M = {}

local conf = require "conf"
local lcd = require "drv_lcd_rgb"
local tpg = require "drv_tp_gt911"

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
    if IS_PC then
        return
    end
    local bl = conf.board.backlight
    -- 背光压灭（pwm.setup 后必须 pwm.start 才会把占空比写进硬件）
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
初始化显示屏（RGB 并口），只做 display，不建界面
@return boolean 成功返回 true
]]
function M.display_on()
    return lcd.init(conf.board.lcd)
end

--[[
初始化 GT911 触摸并绑定到 plcui（必须在 ui_hmi.init 之后调用）
@return boolean|userdata
]]
function M.touch_on()
    return tpg.init(conf.board.tp)
end

--[[
点亮背光（首屏绘制完成后调用）
@param level number 背光亮度 0~100，默认取 conf.board.backlight.level
@return nil
]]
function M.backlight_on(level)
    if IS_PC then
        return
    end
    local bl = conf.board.backlight
    pcall(pwm.setup, bl.pwm_ch, bl.pwm_freq, level or bl.level)
    pcall(pwm.start, bl.pwm_ch)
end

--[[
板级整体初始化（上电 + 屏，不含界面/触摸/背光）
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
