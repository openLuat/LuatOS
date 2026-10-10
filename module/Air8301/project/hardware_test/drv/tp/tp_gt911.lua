--[[
@module  gt911
@summary GT911 触摸控制器驱动（Air8301 硬件测试）
@version 3.0
@date    2026.08.04
@author  江访
@usage
本模块是纯驱动模块，不自动初始化，不等待消息。
由 ui_main.lua 的 init_ui_task 协程在 lcd_init 之后调用 M.init()。

对齐工厂引擎 app_engine 的 tp_gt911.lua 模式：
通过 params 传入端口/引脚/方向等参数，返回 tp_device。
]]
local M = {}

--[[
触摸芯片初始化（不含 AirUI 绑定，绑定由调用方负责）

@param table params  { port, pin_rst, pin_int, w, h, direction, int_type }
@return userdata|nil  tp_device 成功 / nil 失败
]]
function M.init(params)
    params = params or {}

    -- I2C 初始化
    local port = params.port or 0
    local i2c_speed = params.i2c_speed or i2c.SLOW
    i2c.setup(port, i2c_speed)

    -- direction=0（正常方向）：面板已物理旋转180°安装，LCD和TP均用原始坐标
    local tp_device = tp.init("gt911", {
        port     = port,
        pin_rst  = params.pin_rst or 26,
        pin_int  = params.pin_int or gpio.WAKEUP0,
        w        = params.w or 480,
        h        = params.h or 272,
        direction = params.direction or 0,
        int_type = params.int_type or 1,
    })
    if not tp_device then
        log.warn("gt911", "tp.init 失败（PC模拟器可忽略）")
        return nil
    end

    -- 绑定到 AirUI（兼容新/旧固件 API，失败不崩溃）
    local bind_fn = airui.device_bind_touch or airui.indev_bind_touch
    if not bind_fn then
        log.warn("gt911", "airui 无触摸绑定API(device_bind_touch/indev_bind_touch), 建议升级固件")
        return tp_device
    end
    local ok, err = pcall(bind_fn, tp_device)
    if not ok then
        log.warn("gt911", "touch bind failed:", err)
    end

    log.info("gt911", "触摸初始化完成")
    return tp_device
end

return M
