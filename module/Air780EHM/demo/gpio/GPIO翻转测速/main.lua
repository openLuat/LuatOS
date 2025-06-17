-- Luatools需要PROJECT和VERSION这两个信息
PROJECT = "gpio2demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if wdt then
    -- 添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local test_gpio_number = 27

gpio.setup(test_gpio_number, 0, gpio.PULLUP)

sys.taskInit(function()
    sys.wait(100)
    while true do
        sys.wait(100)
        -- 通过GPIO27脚输出输出8组电平变化
        -- 0xA9就是输出的电平高低状态，即 10101001
        gpio.pulse(test_gpio_number, 0xA9, 8, 0)
        log.info("gpio----------->pulse2")
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
