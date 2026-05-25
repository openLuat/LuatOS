--[[
@module  hx8282_10in
@summary HX8282 RGB 10.1寸 1024×600 屏幕驱动
@version 1.0
@date    2026.05.22
@author  江访
@usage
params: { port, pin_rst, pin_pwr, direction, w, h, xoffset, yoffset, hbp, hspw, hfp, vbp, vspw, vfp, bus_speed }
]]
local M = {}

function M.init(params)
    if params.pin_pwr then
        gpio.setup(params.pin_pwr, 0)
        gpio.set(params.pin_pwr, 1)
    end

    local r = lcd.init("hx8282", {
        port      = params.port or lcd.RGB,
        pin_rst   = params.pin_rst or 38,
        direction = params.direction or 0,
        w         = params.w or 1024,
        h         = params.h or 600,
        xoffset   = params.xoffset or 0,
        yoffset   = params.yoffset or 0,
        hbp       = params.hbp or 160,
        hspw      = params.hspw or 70,
        hfp       = params.hfp or 160,
        vbp       = params.vbp or 23,
        vspw      = params.vspw or 20,
        vfp       = params.vfp or 12,
        bus_speed = params.bus_speed or (51 * 1000 * 1000),
    })
    return r
end

return M
