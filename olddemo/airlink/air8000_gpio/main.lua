
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_gpio_ext"
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
    -- 闪灯开始
    sys.wait(100)
    pin = 164
    while 1 do
        gpio.setup(pin, 0, gpio.PULLUP)
        sys.wait(500)
        gpio.setup(pin, 1, gpio.PULLUP)
        sys.wait(500)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
