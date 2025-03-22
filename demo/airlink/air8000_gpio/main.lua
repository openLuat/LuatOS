
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air8000_gpio_ext"
VERSION = "1.0.5"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]

PWR8000S = gpio.setup(23, 0, gpio.PULLUP) -- 关闭Air8000S的LDO供电

sys.taskInit(function()
    -- 稍微缓一下
    sys.wait(10)
    -- 初始化airlink
    airlink.init()
    -- 启动底层线程, 从机模式
    airlink.start(1)
    PWR8000S(1)

    -- 闪灯开始
    sys.wait(100)
    while 1 do
        gpio.setup(109, 0, gpio.PULLUP)
        gpio.setup(108, 1, gpio.PULLUP)
        sys.wait(500)
        gpio.setup(109, 1, gpio.PULLUP)
        gpio.setup(108, 0, gpio.PULLUP)
        sys.wait(500)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
