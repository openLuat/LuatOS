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
    local r = lcd.init("h050iwv", params)
    return r
end

return M
