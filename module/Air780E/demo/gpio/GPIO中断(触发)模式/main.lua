-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpio_irq"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 配置gpio24为中断模式，上升沿(gpio.RISING)和下降沿(gpio.FALLING)均触发(gpio.BOTH)
-- 请根据实际需求更改gpio编号和触发模式
local gpio_pin = 24
gpio.debounce(gpio_pin, 100)
gpio.setup(gpio_pin, function()
    log.info("gpio", gpio_pin, "被触发")
end, gpio.PULLUP, gpio.BOTH)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
