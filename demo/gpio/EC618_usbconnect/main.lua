
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_connect_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
led = gpio.setup(24, 1) --如果真的把USB拔出，可能无法打印出信息，所以拿个IO输出和USB一样状态的电平

gpio.setup(33, function() -- 33是虚拟GPIO，见https://wiki.luatos.com/chips/air780e/iomux.html#id1
    log.info("usb", gpio.get(33))
    led(gpio.get(33))   --IO输出和USB一样的状态
end, gpio.PULLUP, gpio.BOTH)
gpio.debounce(33, 500, 1)  --加入消抖是为了尽量能看到输出
log.info("usb", gpio.get(33))
led(gpio.get(33)) --IO输出和USB一样的状态
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
