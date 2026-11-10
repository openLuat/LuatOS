--[[
@module  drv_tp_gt911
@summary GT911 触摸控制器驱动（Air8603W1 I2C1 + GPIO14 复位 + GPIO51 中断）
@version 1.0.0
@date    2026.11.09

执行 I2C 初始化 → tp.init → airui 绑定。
复位由内核 tp 驱动的 tp_gt9xx_gpio_init 完成，脚本里不再重复拉 RST（双复位会导致
地址识别失败）。tp.init 一次上电只能成功一次，故只认首次调用，重复调用直接返回。
]]
local M = {}

local tp_device = nil

function M.init(params)
    if tp_device then
        return tp_device
    end

    if rtos.bsp() == "PC" then
        log.info("drv_tp_gt911", "PC 模拟器跳过触摸初始化")
        return true
    end

    -- 复位交给内核驱动（tp.init 内部做 RST 低 → INT 低锁 0x14 → RST 高 → 2ms → 55ms）
    -- I2C 轮询模式：触摸坐标在 TP 中断路径里突发读，中断驱动 I2C 与嵌套中断
    -- 相互干扰时会"仅触摸时"报 I2C 错误，轮询模式可根治
    local ok_i2c = pcall(i2c.setup, params.port, 0, true)
    if not ok_i2c then
        log.error("drv_tp_gt911", "i2c.setup 失败, port", params.port)
        return false
    end

    local tp_params = {
        port    = params.port,
        pin_rst = params.pin_rst,
        pin_int = params.pin_int,
        w       = params.w,
        h       = params.h,
    }
    if tp.FALLING then
        tp_params.int_type = tp.FALLING
    end

    local r = tp.init("gt911", tp_params)
    if not r then
        log.error("drv_tp_gt911", "tp.init 失败")
        return false
    end
    tp_device = r

    local ok = pcall(airui.device_bind_touch, r)
    log.info("drv_tp_gt911", ok and "初始化成功并已绑定 airui" or "初始化成功但绑定 airui 失败")
    return r
end

return M
