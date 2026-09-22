--[[
@module  hx8282
@summary HX8282 RGB 7/10.1寸 1024×600 通用屏幕驱动
@version 2.0
@date    2026.05.25
@author  江访
@usage
params: { port, pin_rst, pin_pwr(可选), direction, w, h, xoffset, yoffset, hbp, hspw, hfp, vbp, vspw, vfp, bus_speed }
]]
local M = {}

function M.init(params)
    if params.pin_pwr then
        gpio.setup(params.pin_pwr, 0)
        gpio.set(params.pin_pwr, 1)
    end

    local r = lcd.init("hx8282", params)
    return r
end

return M
