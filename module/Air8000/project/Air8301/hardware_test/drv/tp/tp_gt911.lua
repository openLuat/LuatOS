--[[
@module  gt911
@summary GT911 触摸控制器驱动（Air8301 硬件测试）
@version 2.0
@date    2026.08.04
@author  江访
@usage
require "tp_gt911" 即完成触摸初始化（等待 DISPLAY_READY 后执行，绑定到 AirUI）。
]]

--[[
触摸初始化协程（require 后自动启动，含 sys.wait 延时）：
1. 等待 DISPLAY_READY 消息（需 LCD/AirUI 先就绪）
2. 初始化 I2C0 并复位 GT911（pin_rst=GPIO26, pin_int=WAKEUP0）
3. tp.init 初始化触摸芯片
4. 绑定触摸设备到 AirUI（兼容 device_bind_touch / indev_bind_touch，失败不崩溃）

@local
@function tp_init_task
]]
local function tp_init_task()
    -- 等待 LCD/AirUI 初始化完成
    sys.waitUntil("DISPLAY_READY", 5000)

    -- I2C 上电稳定
    i2c.setup(0, i2c.SLOW)
    sys.wait(100)

    -- direction=2(180°)：Air8301 TP 原点在右下角，LCD 原点在左上角，需翻转 X/Y
    -- C 层变换：x_new = w - x_raw, y_new = h - y_raw
    local tp_device = tp.init("gt911", {
        port = 0,
        pin_rst = 26,
        pin_int = gpio.WAKEUP0,
        w = 480,
        h = 272,
        direction = 2,
        int_type = 1,
    })
    if not tp_device then
        log.warn("gt911", "tp.init 失败（PC模拟器可忽略）")
        return
    end

    -- 绑定到 AirUI（兼容新/旧固件 API，失败不崩溃）
    local bind_fn = airui.device_bind_touch or airui.indev_bind_touch
    if not bind_fn then
        log.warn("gt911", "airui 无触摸绑定API(device_bind_touch/indev_bind_touch), 建议升级固件")
        return
    end
    local ok, err = pcall(bind_fn, tp_device)
    if not ok then
        log.warn("gt911", "touch bind failed:", err)
        return
    end
    log.info("gt911", "触摸初始化完成")
end

sys.taskInit(tp_init_task)
