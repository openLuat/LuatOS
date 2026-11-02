--[[
@module  gt911
@summary GT911 触摸控制器通用驱动
@version 1.1
@date    2026.10.23
@author  江访
@usage
传入底板接线参数，执行 GPIO复位 → I2C初始化 → tp.init → airui绑定
params: { port, pin_rst, pin_int, int_type, i2c_speed, w, h, gpio_reset }
触摸芯片只初始化一次：init 重复调用直接返回已初始化的设备对象，不再碰 tp.init
]]
local M = {}

-- tp.init 返回的触摸设备对象，非 nil 即已初始化成功
-- 内核 tp 库一次上电只接受一次 tp.init（luat_lib_tp.c 的 s_init，成功即置位），
-- 二次调用打印 E/tp tp has been initialized!!! 并返回 nil，故只认首次成功
local tp_device = nil

function M.init(params)
    -- 已初始化过：内核 tp 库只接受一次 tp.init，直接返回设备对象
    if tp_device then
        return tp_device
    end
    -- GPIO 复位序列（部分底板需要）
    if params.gpio_reset then
        gpio.setup(params.gpio_reset, 0)
        gpio.close(params.gpio_reset)
    end

    -- I2C 初始化
    -- 第三参 true = 轮询模式（API 文档原话："除非使用中有问题，否则留空"）。
    -- 触摸坐标在 TP 中断路径里突发读，中断驱动 I2C 与嵌套中断相互干扰时，
    -- 会恰好"仅触摸时"报 I2C 错误 —— 轮询模式根治；触摸带宽极小，性能无感。
    -- params.i2c_polling 可显式传 false 回退平台默认（中断模式）。
    local polling = params.i2c_polling
    if polling == nil then polling = true end
    if params.i2c_speed then
        i2c.setup(params.port, params.i2c_speed, polling)
    else
        i2c.setup(params.port, 0, polling)
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
    if not r then return false end
    -- 成功即封口：内核 s_init 已置位，之后任何路径都不再调 tp.init
    tp_device = r

    -- PC 模拟跳过绑定（用鼠标替代）
    if _G.project_config and _G.project_config.chip == "PC" then
        log.info("gt911", "PC模式，跳过触摸绑定")
        return r
    end

    airui.device_bind_touch(r)
    return r
end

return M
