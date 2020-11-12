
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

local NETLED = gpio.setup(19, 0, gpio.PULLUP) -- 输出模式
local G18 = gpio.setup(18, 0, gpio.PULLUP) -- 输出模式
local G7 = gpio.setup(7, function() -- 中断模式, 下降沿，需要将GPIO18和GPIO7连在一起
    log.info("gpio7", "BOOT button release")
end, gpio.PULLUP,gpio.FALLING)
local G1 = gpio.setup(1, function() -- 中断模式, 下降沿
    log.info("gpio1", "BOOT button release")
end, gpio.PULLUP,gpio.FALLING)
sys.taskInit(function()

    while 1 do
        -- 一闪一闪亮晶晶
        NETLED(0)
        G18(0)
        log.info("gpio", "7", G7())
        sys.wait(500)
        NETLED(1)
        G18(1)
        sys.wait(500)
        log.info("gpio", "7", G7())
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
