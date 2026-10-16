--[[
@module  gt911
@summary GT911 触摸控制器通用驱动
@version 1.0
@date    2026.05.22
@author  江访
]]
local M = {}

function M.init(params)
    if params.pwr_pins then
        for _, p in ipairs(params.pwr_pins) do
            gpio.setup(p.pin, 1, gpio.PULLUP)
        end
    end
    local delay = params.pwr_pins and (params.pwr_delay or 100) or params.pwr_delay
    if delay and delay > 0 then
        sys.wait(delay)
    end

    if params.gpio_reset then
        gpio.setup(params.gpio_reset, 0)
        gpio.close(params.gpio_reset)
    end

    if params.i2c_speed then
        i2c.setup(params.port, params.i2c_speed)
    else
        i2c.setup(params.port)
    end

    local tp_params = {
        port    = params.port,
        pin_rst = params.pin_rst,
        pin_int = params.pin_int,
    }
    if params.int_type then tp_params.int_type = params.int_type end
    if params.w then tp_params.w = params.w end
    if params.h then tp_params.h = params.h end

    local r = tp.init("gt911", tp_params)
    log.info("gt911", r and "初始化成功" or "初始化失败")

    if r then
        airui.device_bind_touch(r)
    end
    return r
end

return M
