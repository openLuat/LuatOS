
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")


gpio.setup(21, function()
    log.info("gpio", "AON_GPIO2")
end, gpio.PULLDOWN)
gpio.setup(23, function()
    log.info("gpio", "AON_GPIO3")
end, gpio.PULLDOWN)
--end

-- sys.taskInit(function()
--     local val = 0
--     while 1 do
--         -- 一闪一闪亮晶晶
--         val = val == 0 and 1 or 0
--         --for i=21,23 do
--             log.info("gpio", 21,  val)
--             gpio.set(21, val)
--             sys.wait(500)
--             log.info("gpio", 23,  val)
--             gpio.set(23, val)
--             sys.wait(500)
--         --end
--         --log.info("gpio", val)
        
--     end
-- end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
