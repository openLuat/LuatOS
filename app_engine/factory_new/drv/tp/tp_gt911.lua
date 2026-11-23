--[[
@module  gt911
@summary GT911 触摸控制器通用驱动
@version 1.4
@date    2026.11.19
@author  江访
@usage
传入底板接线参数，配置 I2C、完成触摸复位后将设备绑定到 AirUI。
params: { port, pin_rst, pin_int, int_type, i2c_speed, w, h, gpio_reset, reset_hold_ms, rst_external_pullup }
触摸芯片只初始化一次：init 重复调用直接返回已初始化的设备对象，不再碰 tp.init
]]
local M = {}

local tp_device = nil
local touch_bound = false
local retry_with_rst_input = false

local function bind_touch()
    if not touch_bound then
        if not airui.device_bind_touch(tp_device) then return false, "AirUI 触摸绑定失败" end
        touch_bound = true
        log.info("gt911", "READY", "初始化成功，已绑定 AirUI")
    end
    return tp_device
end

function M.init(params)
    if _G.is_pc or (_G.project_config and _G.project_config.chip == "PC") then return true end
    -- V1032 accepts one successful tp.init. A failed AirUI bind can be retried on that handle.
    if tp_device then return bind_touch() end
    -- GPIO 复位序列（部分底板需要）
    if params.gpio_reset then
        gpio.setup(params.gpio_reset, 0)
        gpio.close(params.gpio_reset)
    end

    -- Keep the existing polling preference for BSPs that implement the option.
    local polling = params.i2c_polling
    if polling == nil then polling = true end
    if i2c.setup(params.port, params.i2c_speed or 0, polling) ~= 1 then
        return false, "I2C" .. params.port .. " 初始化失败"
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

    local rst_released
    if params.reset_hold_ms then
        -- The first attempt hands both pins to the native driver while still low.
        if not gpio.setup(params.pin_rst, 0) then return false, "TP_RST 配置失败" end
        sys.wait(params.reset_hold_ms)
        if not gpio.setup(params.pin_int, 0) then
            gpio.set(params.pin_rst, 1)
            if params.rst_external_pullup then gpio.setup(params.pin_rst, nil, 0) end
            return false, "TP_INT 配置失败"
        end
        sys.wait(2) -- INT low across the reset rising edge selects 7-bit address 0x5D.
        if retry_with_rst_input and params.rst_external_pullup then
            -- Keep GPIO ownership across the retry. R16 holds RST high after the pulse.
            gpio.set(params.pin_rst, 1)
            sys.wait(6)
            rst_released = gpio.setup(params.pin_rst, nil, 0)
            if not rst_released then
                gpio.setup(params.pin_int, nil, 0)
                return false, "TP_RST 输入配置失败"
            end
            sys.wait(55)
            -- Complete Goodix INT sync before the first address phase. Use V1032 polling
            -- on this retry so the native driver cannot drive the physical INT low again.
            if not gpio.setup(params.pin_int, nil, 0) then return false, "TP_INT 输入配置失败" end
            tp_params.pin_rst, tp_params.pin_int = 0xff, 0xff
        end
    end
    tp_device = tp.init("gt911", tp_params)
    if not tp_device then
        if params.rst_external_pullup then
            retry_with_rst_input = true
            -- Native failure cleanup can restore LCD_D16 on GPIO72. Keep TP2-1 in GPIO mode.
            if not rst_released and not gpio.setup(params.pin_rst, nil, 0) then
                return false, "TP_RST 输入配置失败"
            end
        end
        return false, "GT911 探测或配置失败，见 gt9xx 日志"
    end
    return bind_touch()
end

return M
