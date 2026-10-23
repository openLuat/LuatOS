--[[
@module gt911
@summary GT911 触摸控制器通用驱动
@version 1.0
@date 2026.05.22
@author 江访
@usage Air8601 标配 7 寸电容触摸（GT911，I2C1）。本文件取自合宙官方
       module/Air8601/project/factory/user/tp_gt911.lua，未做改动。
]]

local M = {}

function M.init(params)
    -- 1. 触摸芯片上电（若有电源控制引脚）
    if params.pwr_pins then
        for _, p in ipairs(params.pwr_pins) do
            gpio.setup(p.pin, 1, gpio.PULLUP)
        end
    end

    -- 2. 上电后延时等待芯片就绪
    local delay = params.pwr_pins and (params.pwr_delay or 100) or params.pwr_delay
    if delay and delay > 0 then
        sys.wait(delay)
    end

    -- 3. 复位引脚：拉低后释放（gpio.close）以完成复位时序
    if params.gpio_reset then
        gpio.setup(params.gpio_reset, 0)
        gpio.close(params.gpio_reset)
    end

    -- 4. 初始化 I2C 总线（可选指定速率）
    if params.i2c_speed then
        i2c.setup(params.port, params.i2c_speed)
    else
        i2c.setup(params.port)
    end

    -- 5. 组装 tp.init 参数表
    local tp_params = {
        port    = params.port,
        pin_rst = params.pin_rst,
        pin_int = params.pin_int,
    }
    if params.int_type then tp_params.int_type = params.int_type end
    if params.w then tp_params.w = params.w end
    if params.h then tp_params.h = params.h end

    -- 6. 调用 LuatOS 通用触摸层初始化 GT911
    local r = tp.init("gt911", tp_params)
    log.info("gt911", r and "初始化成功" or "初始化失败")

    -- 7. 初始化成功后绑定到 AirUI 触摸设备
    if r then
        airui.device_bind_touch(r)
    end

    return r
end

return M
