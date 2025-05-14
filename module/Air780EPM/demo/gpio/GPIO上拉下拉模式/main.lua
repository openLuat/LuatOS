-- Luatools需要PROJECT和VERSION这两个信息
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

--配置gpio7为中断上拉模式
--配置gpio27为中断下拉模式
--请根据实际需求更改gpio编号和上下拉
local gpio_pin1 = 7
local gpio_pin2 = 27
-- 按键防抖函数
gpio.debounce(gpio_pin1, 50)
gpio.debounce(gpio_pin2, 50)

-- 设置GPIO7引脚为上拉输入模式
gpio.setup(gpio_pin1, nil, gpio.PULLUP)

-- 设置GPIO27引脚为下拉输入模式
gpio.setup(gpio_pin2, nil, gpio.PULLDOWN)


sys.timerLoopStart(function ()
    log.info("GPIO",gpio_pin1,"电平",gpio.get(gpio_pin1))
    log.info("GPIO",gpio_pin2,"电平",gpio.get(gpio_pin2))
end,1000)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!