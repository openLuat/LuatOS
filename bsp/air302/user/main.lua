
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "air302_gpio_demo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

local NETLED = gpio.setup(19, 0) -- 输出模式
local G18 = gpio.setup(18, nil) -- 输入模式
local G1 = gpio.setup(1, function() -- 中断模式, 下降沿
    log.info("gpio", "BOOT button release")
end)

sys.taskInit(function()
    while 1 do
        -- 一闪一闪亮晶晶
        NETLED(0)
        sys.wait(500)
        NETLED(1)
        sys.wait(500)
        log.info("gpio", "18", G18())
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
