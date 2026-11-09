--[[
@module  touch_panel
@summary GT911 触摸初始化并绑定到 AirUI
@version 1.0
@date    2026.11.08

=== 轮询模式的必要性 ===
GT911 走中断模式时，I2C 总线被音频/视频库重配后容易丢点，
表现是「画面正常但点击没反应」。工程里统一用轮询模式（i2c.setup 的第三参 true）。
]]

local M = {}

function M.init(conf)
    if rtos.bsp() == "PC" then
        log.info("touch_panel", "PC 模拟器使用 SDL 鼠标输入，跳过 tp.init")
        return false
    end

    -- 先在驱动层把 I2C 切成轮询模式，tp.init 内部复用这条总线
    pcall(i2c.setup, conf.port, 0, true)

    local dev, err = tp.init("gt911", {
        port     = conf.port,
        pin_rst  = conf.pin_rst,
        pin_int  = conf.pin_int,
        int_type = tp.FALLING,
        w        = conf.w,
        h        = conf.h,
    })
    if not dev then
        log.error("touch_panel", "tp.init 失败", err)
        return false
    end

    airui.device_bind_touch(dev)
    log.info("touch_panel", "GT911 已绑定")
    return true
end

return M
