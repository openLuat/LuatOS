--[[
@module  custom_evb_10in
@summary RGB 10.1寸 1024×600 屏幕驱动（Air1601 EVB 底板，时序参数不同）
@version 1.0
@date    2026.05.22
@author  江访
@usage
params: { port, pin_rst, direction, w, h, xoffset, yoffset, hbp, hspw, hfp, vbp, vspw, vfp, bus_speed }
]]
local M = {}

function M.init(params)
    local r = lcd.init("custom", {
        port      = params.port or lcd.RGB,
        pin_rst   = params.pin_rst,
        direction = params.direction or 0,
        w         = params.w or 1024,
        h         = params.h or 600,
        xoffset   = params.xoffset or 0,
        yoffset   = params.yoffset or 0,
        -- EVB 底板时序（与 Air1601 底板不同）
        hbp       = params.hbp,
        hspw      = params.hspw,
        hfp       = params.hfp,
        vbp       = params.vbp,
        vspw      = params.vspw,
        vfp       = params.vfp,
        bus_speed = params.bus_speed or (51 * 1000 * 1000),
    })
    return r
end

return M
