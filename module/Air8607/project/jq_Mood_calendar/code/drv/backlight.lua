--[[
@module  backlight
@summary 背光 PWM 控制（PWM3 / GPIO13）
@author  蒋骞
@version 1.0
@date    2026.10.30

=== 为什么要先关再开 ===
上电时先给 0 占空比，等显示初始化和界面都搭好之后再点亮，
否则会看到一段花屏。所有工程都按这个顺序做。
]]
local conf = require "conf"

local M = {}

local CH = conf.backlight.pwm_ch
local FREQ = conf.backlight.freq

--[[上电先关背光（占空比 0）]]
function M.off()
    if pwm and pwm.setup then
        pwm.setup(CH, FREQ, 0)
        pwm.start(CH)
    end
end

--[[按默认亮度点亮]]
function M.on(pct)
    pct = pct or conf.backlight.default
    if pct < 10 then pct = 10 end      -- 下限防止全黑把自己锁在门外
    if pct > 100 then pct = 100 end
    if pwm and pwm.setup then
        pwm.setup(CH, FREQ, pct)
        pwm.start(CH)
    end
    return pct
end

return M
