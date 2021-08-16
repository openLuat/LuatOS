
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")


gpio.setup(7, function()
    log.info("gpio", "PA7")
end, gpio.PULLDOWN)

sys.taskInit(function()
    while 1 do
        sys.wait(500)
    end
end)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
