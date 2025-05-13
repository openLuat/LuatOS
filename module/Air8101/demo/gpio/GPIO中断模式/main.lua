-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "GPIO_irq"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

-- 配置GPIO为中断模式，上升沿(GPIO.RISING)和下降沿(GPIO.FALLING)，需要注意的是air8101只能支持单边沿中断
-- 请根据实际需求更改GPIO编号和触发模式
local GPIO_pin = 1
gpio.debounce(GPIO_pin, 100)
gpio.setup(GPIO_pin, function()
    log.info("GPIO", GPIO_pin, "被触发")
end,gpio.PULLDOWN,gpio.RISING)

-- 在测试中，我们初始化GPIO0为输出模式，每隔一秒翻转一次输出电平，然后将此管脚与中断管脚相连
local gpio_number = 0
gpio_out = gpio.setup(gpio_number, 1)
sys.taskInit(function()
    while 1 do
        gpio_out(1)
        log.info("GPIO0 高")
        sys.wait(1000)
        gpio_out(0)
        log.info("GPIO0 低")
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!