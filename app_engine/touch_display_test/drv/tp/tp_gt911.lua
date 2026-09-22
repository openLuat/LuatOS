--[[
@module  gt911
@summary GT911 触摸控制器通用驱动
@version 1.0
@date    2026.05.22
@author  江访
@usage
传入底板接线参数，执行 GPIO复位 → I2C初始化 → tp.init → airui绑定
params: { port, pin_rst, pin_int, int_type, i2c_speed, w, h, gpio_reset }
]]
local M = {}

function M.init(params)
    -- 底板 I2C 供电 GPIO 上拉（部分平台需要在 I2C 初始化前配置）
    if params.pwr_pins then
        for _, p in ipairs(params.pwr_pins) do
            gpio.setup(p.pin, 1, gpio.PULLUP)
        end
    end
    -- I2C 上电稳定等待（默认 0，有 pwr_pins 或显式设 pwr_delay 时才等）
    local delay = params.pwr_pins and (params.pwr_delay or 100) or params.pwr_delay
    if delay and delay > 0 then
        sys.wait(delay)
    end

    -- GPIO 复位序列（部分底板需要）
    if params.gpio_reset then
        gpio.setup(params.gpio_reset, 0)
        gpio.close(params.gpio_reset)
    end

    -- I2C 初始化
    if params.i2c_speed then
        i2c.setup(params.port, params.i2c_speed)
    else
        i2c.setup(params.port)
    end

    -- tp.init
    local tp_params = {
        port    = params.port,
        pin_rst = params.pin_rst,
        pin_int = params.pin_int,
    }
    if params.int_type then tp_params.int_type = params.int_type end
    if params.w then tp_params.w = params.w end
    if params.h then tp_params.h = params.h end

    local r = tp.init("gt911", tp_params)
    log.info("gt911", r and "初始化成功" or "初始化失败，PC模拟器可以忽略")

    -- PC 模拟跳过绑定（用鼠标替代）
    if _G.project_config and _G.project_config.chip == "PC" then
        log.info("gt911", "PC模式，跳过触摸绑定")
        return r
    end

    if r then
        airui.device_bind_touch(r)
    end
    return r
end

return M
