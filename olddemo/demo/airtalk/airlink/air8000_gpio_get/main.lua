
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_gpio_get"
VERSION = "1.0.5"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]

-- 通过boot按键方便刷Air8000S
function PWR8000S(val)
    gpio.set(23, val)
end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

sys.taskInit(function()

    -- GPIO153 输出电平
    -- GPIO160 读取电平
    sys.wait(3000)
    IN = gpio.setup(160, nil, gpio.PULLUP)
    OUT = gpio.setup(153, 0, gpio.PULLUP)
    while 1 do
        gpio.toggle(153)
        log.info("gpio", "读出的值是", gpio.get(160)) 
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
