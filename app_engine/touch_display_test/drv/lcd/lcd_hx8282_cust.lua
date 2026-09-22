--[[
@module  hx8282_custom
@summary HX8282 RGB 7/10.1寸 1024×600 屏幕驱动（custom 裸传方式）
@version 1.0
@date    2026.07.22
@author  江访
@usage
适配四合一屏模组（内部自带控制芯片），使用 custom 方式裸传时序参数，不触发 IC 初始化序列。
params 原样透传给 lcd.init("custom", params)，支持以下参数：
  port, pin_rst, pin_pwr, direction, w, h, xoffset, yoffset,
  hbp, hspw, hfp, vbp, vspw, vfp, bus_speed, pclk, rb_swap
]]
local M = {}

function M.init(params)
    if params.pin_pwr then
        gpio.setup(params.pin_pwr, 0)
        gpio.set(params.pin_pwr, 1)
    end

    local r = lcd.init("custom", params)
    return r
end

return M
