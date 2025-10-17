
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpio2demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

--配置gpio7为输入模式，下拉，并会触发中断
--请根据实际需求更改gpio编号和上下拉
local gpio_pin = 7
gpio.setup(gpio_pin, gpio.count, gpio.PULLUP, gpio.FALLING)
pwm.open(1,2000,50) --2k 50%占空比作为触发源
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.taskInit(function()
    while true do
        sys.wait(999)
        log.info("irq cnt", gpio.count(gpio_pin))
    end
end)
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
