--[[
@module  tp_drv
@summary GT911 触摸驱动模块（Air8301）
@version 1.0
@date    2026.09.18
@author  嵌入式软件设计开发代理
@usage
本模块由 Air8000A 版本 tp_drv 移植而来，触摸 IC 同为 GT911，参数适配 Air8301 硬件。
参考：module/Air8000/project/Air8301/hardware_test/drv/tp/tp_gt911.lua

功能：
1、初始化 GT911 触摸控制器（I2C0，复位 GPIO26，中断 WAKEUP0）；
2、绑定触摸设备到 AirUI 输入设备（airui.device_bind_touch）。

对外接口：
- tp_drv.init()  初始化触摸面板驱动
]]

local tp_drv = {}

--[[
初始化触摸面板驱动（不含 AirUI 触摸绑定由本函数内部完成）

@api tp_drv.init()
@summary 配置并初始化 GT911 触摸控制器并绑定 AirUI
@return userdata|nil  tp_device 成功 / nil 失败
]]
function tp_drv.init()
    -- 初始化硬件 I2C（Air8301 触摸使用 I2C0）
    i2c.setup(0, i2c.SLOW)

    -- GT911 触摸初始化
    -- 参数说明（Air8301 硬件测试板）：
    --   port      : I2C 接口
    --   pin_rst   : 复位引脚 GPIO26
    --   pin_int   : 中断引脚 WAKEUP0
    --   w / h     : LCD 显示分辨率 480x272
    --   direction : 0（面板已物理旋转180°安装，LCD/TP 均用原始坐标）
    --   int_type  : 1
    -- pcall 包裹：PC 模拟器 / 不同固件下 tp.init 可能直接抛异常（而非返回 nil），
    -- 触摸初始化失败不应中断整个应用
    local call_ok, tp_device = pcall(tp.init, "gt911", {
        port      = 0,
        pin_rst   = 26,
        pin_int   = gpio.WAKEUP0,
        w         = 480,
        h         = 272,
        direction = 0,
        int_type  = 1,
    })
    if not call_ok then
        log.warn("tp_drv", "tp.init 异常:", tostring(tp_device))
        return nil
    end
    if not tp_device then
        log.warn("tp_drv", "tp.init 失败（PC模拟器可忽略）")
        return nil
    end

    -- 绑定触摸设备到 AirUI 输入设备（兼容新/旧固件 API，失败不崩溃）
    local bind_fn = airui.device_bind_touch or airui.indev_bind_touch
    if not bind_fn then
        log.warn("tp_drv", "airui 无触摸绑定API(device_bind_touch/indev_bind_touch)")
        return tp_device
    end
    local ok, err = pcall(bind_fn, tp_device)
    if not ok then
        log.warn("tp_drv", "touch bind failed:", err)
    end

    log.info("tp_drv", "GT911 触摸初始化完成")
    return tp_device
end

return tp_drv
