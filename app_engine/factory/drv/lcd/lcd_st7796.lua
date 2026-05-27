--[[
@module  st7796
@summary ST7796 SPI 屏幕驱动（3.5/4寸，320×480 或 480×320）
@version 1.0
@date    2026.05.22
@author  江访
@usage
传入底板接线参数，执行 lcd.init("st7796", ...)
params: { port, pin_rst, pin_pwr, direction, w, h, xoffset, yoffset, pwr_pins }
]]
local M = {}

function M.init(params)
    -- 底板供电控制
    if params.pwr_pins then
        for _, p in ipairs(params.pwr_pins) do
            gpio.setup(p.pin, 1)
            gpio.set(p.pin, p.val)
        end
    elseif params.pin_pwr then
        gpio.setup(params.pin_pwr, 1)
        gpio.set(params.pin_pwr, 1)
    end

    local r = lcd.init("st7796", {
        port      = params.port,
        pin_rst   = params.pin_rst,
        direction = params.direction or 0,
        w         = params.w,
        h         = params.h,
        xoffset   = params.xoffset or 0,
        yoffset   = params.yoffset or 0,
        bus_speed = params.bus_speed,
    })
    return r
end

return M
