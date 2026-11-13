--[[
@module  drv_tp_gt911
@summary GT911 触摸控制器驱动（Air8603W1 I2C1 + GPIO14 复位 + GPIO51 中断）
@version 2.0.0
@date    2026.11.12

与 airui 版的差别：
  只做 i2c.setup + tp.init，把设备句柄返回给调用方；
  绑定动作交给 plcui.device_bind_touch，且必须在 plcui.init 之后调用
  （plcui 的固定顺序：i2c.setup → tp.init → plcui.init → device_bind_touch）。

复位由内核 tp 驱动的 tp_gt9xx_gpio_init 完成，脚本里不再重复拉 RST
（双复位会导致地址识别失败）。tp.init 一次上电只能成功一次，重复调用直接返回缓存。
]]
local M = {}

local tp_device = nil

--[[
初始化触摸控制器
@param params table { port, pin_rst, pin_int, w, h }
@return userdata|boolean|nil 成功返回 tp 设备句柄（PC 模拟器返回 true），失败返回 nil
]]
function M.init(params)
    if tp_device then
        return tp_device
    end

    if rtos.bsp() == "PC" then
        log.info("drv_tp_gt911", "PC 模拟器跳过触摸初始化")
        return true
    end

    -- I2C 轮询模式：触摸坐标在 TP 中断路径里突发读，中断驱动 I2C 与嵌套中断
    -- 相互干扰时会"仅触摸时"报 I2C 错误，轮询模式可根治
    local ok_i2c = pcall(i2c.setup, params.port, 0, true)
    if not ok_i2c then
        log.error("drv_tp_gt911", "i2c.setup 失败, port", params.port)
        return nil
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
        return nil
    end

    tp_device = r
    log.info("drv_tp_gt911", "tp.init 成功")
    return r
end

return M
