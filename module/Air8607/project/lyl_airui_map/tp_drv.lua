--[[
@module  tp_drv
@summary Air8607 GT911 电容触摸，初始化成功后绑定 AirUI
@version 1.0
@date    2026.10.28
@usage
与 projects/airui_button 相同：
tp_drv.init() -> i2c.setup -> tp.init("gt911", ...) -> airui.device_bind_touch()
必须在 display.init 之后、隔 100ms 再调用，否则 RGB 初始化会拆掉触摸中断。
]]

local tp_drv = {}

--[[
初始化触摸面板
@return boolean 成功返回 true
]]
function tp_drv.init()
    if rtos.bsp() == "PC" then
        log.info("tp_drv", "PC 仿真跳过 tp.init")
        return true
    end

    -- GT911 挂在 I2C1，复位脚与 airui_button 一致
    i2c.setup(1)

    local r = tp.init("gt911", {
        port     = 1,
        pin_rst  = 72,
        pin_int  = 51,
        int_type = tp.FALLING,
        w        = _G.screen_w or 1024,
        h        = _G.screen_h or 600,
    })
    log.info("tp_drv", "tp.init", r)
    if not r then
        log.error("tp_drv", "触摸初始化失败")
        return false
    end

    local ok = airui.device_bind_touch(r)
    log.info("tp_drv", "device_bind_touch", ok)
    return ok and true or false
end

return tp_drv
