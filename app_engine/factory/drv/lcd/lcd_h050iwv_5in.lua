--[[
@module  lcd_h050iwv_5in
@summary H050IWV RGB 5寸 800×480 屏幕驱动
@version 1.0
@date    2026.06.18
@author  江访
@usage
params: { port, pin_rst, direction, w, h, xoffset, yoffset }
]]
local M = {}

function M.init(params)
    local r = lcd.init("h050iwv", {
        port      = params.port or lcd.RGB,
        pin_rst   = params.pin_rst,
        direction = params.direction or 0,
        w         = params.w or 800,
        h         = params.h or 480,
        xoffset   = params.xoffset or 0,
        yoffset   = params.yoffset or 0,
        -- hbp       = params.hbp or 46,
        -- hspw      = params.hspw or 2,
        -- hfp       = params.hfp or 48,
        -- vbp       = params.vbp or 24,
        -- vspw      = params.vspw or 2,
        -- vfp       = params.vfp or 24,
        -- bus_speed = params.bus_speed or (51 * 1000 * 1000),
    })
    return r
end

return M
