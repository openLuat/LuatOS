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

    -- 兜底：tp 未显式给 w/h 时，从 LCD 配置继承尺寸。
    -- LCD 驱动改用 display 库后不再调用 lcd.init("custom", ...) 注册内核默认 LCD 配置，
    -- 内核 luat_lcd_get_default() 取不到 w/h → tp 尺寸为 0 → input 适配器以 EINVAL 静默拒绝，
    -- 现象是“能读到 product id 但初始化失败”。
    if not (tp_params.w and tp_params.h) then
        local lcd_cfg = _G.project_config and _G.project_config.hw
                        and _G.project_config.hw.lcd
        local lp = lcd_cfg and lcd_cfg.params
        -- 仅补偿走 display 库的 LCD：lcd_display_rgb 内部改用 display.init、
        -- 不再调用 lcd.init("custom", ...)，内核 lcd_conf 里没有尺寸可继承，
        -- 缺 w/h 会让 input 适配器以 EINVAL 静默拒绝（能读到 product id 但初始化失败）。
        -- 走旧 lcd 库(st7796/st6201…)的板内核仍有默认 lcd 配置，保持原行为不动。
        if lcd_cfg and lcd_cfg.model == "lcd_display_rgb" then
            if type(lp) == "table" then
                tp_params.w = tp_params.w or lp.w
                tp_params.h = tp_params.h or lp.h
            end
            if tp_params.w and tp_params.h then
                log.info("gt911", "tp 尺寸未配置，继承 LCD:", tp_params.w, tp_params.h)
            else
                log.warn("gt911", "tp 尺寸缺失(w/h 为空)，触摸初始化必然失败，请检查 lcd/tp 配置")
            end
        end
    end

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
