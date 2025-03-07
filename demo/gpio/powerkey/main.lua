
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pwrkey_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

if gpio.PWR_KEY then
    gpio.setup(gpio.PWR_KEY, function() 
        log.info("pwrkey", gpio.get(gpio.PWR_KEY))
    end, gpio.PULLUP)
else
    log.info("bsp not support")
end


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
