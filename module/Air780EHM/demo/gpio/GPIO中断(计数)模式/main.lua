-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "gpio_irq"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

--配置gpio24为中断计数模式
--请根据实际需求更改gpio编号和上下拉
local gpio_pin = 24
-- gpio.setup(gpio_pin, gpio.count, gpio.PULLUP, gpio.FALLING)
gpio.setup(gpio_pin, gpio.count)

--配置PWM4输出 1kHZ 占空比50%的方波作为信号源
pwm.open(4,1000,50)

--每隔1S统计一次中断触发的次数
sys.taskInit(function()
    while true do
        sys.wait(1000)
        log.info("irq cnt", gpio.count(gpio_pin))
    end
end)

sys.run()
-- sys.run()之后后面不要加任何语句!!!!!