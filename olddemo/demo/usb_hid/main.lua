PROJECT = "usb_hid_demo"
VERSION = "1.3.3"

sys = require("sys")

log.style(1)

local function air1601_evb_init()
    gpio.setup(12, 1, gpio.PULLUP) -- 输出高，内部上拉可选
end

sys.taskInit(function()
    require("lcd_drv")
    require("hid_lvgl")
    require("input_demo")
    require("tp_drv")
    pm.power(pm.USB, false)
    sys.wait(100) -- USB电源操作由C任务异步执行，等待关闭后再切换模式
    air1601_evb_init()
    sys.wait(100) -- 等待开发板VBUS供电稳定
    usb.debug(0, false) -- 保留 C HID/input 日志，关闭底层控制传输刷屏
    assert(usb.mode(0, usb.HOST), "USB Host mode failed")
    pm.power(pm.USB, true)
    log.info("usb_hid", "HID_C_HOST_READY", VERSION)
    while true do
        sys.wait(10000)
        log.info("usb_hid", "HID_C_HOST_STABLE", VERSION)
    end
end)

-- 用户代码已结束，启动系统调度。
sys.run()
