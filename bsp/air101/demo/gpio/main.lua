
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

local LED = gpio.setup(7, 0, gpio.PULLUP) -- PB1输出模式

local G1 = gpio.setup(1, function() -- 中断模式, 下降沿，需要将PB1和PA1连在一起
    log.info("PA1", "BOOT button release")
end, gpio.PULLUP,gpio.FALLING)

sys.taskInit(function()
    while 1 do
        -- 一闪一闪亮晶晶
        LED(0)
        log.info("gpio", "1", G1())
        sys.wait(500)
        LED(1)
        sys.wait(500)
        log.info("gpio", "1", G1())
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
