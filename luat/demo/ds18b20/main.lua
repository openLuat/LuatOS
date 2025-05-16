
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dht12"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    local ds18b20_pin = 8
    while 1 do
        sys.wait(1000)
        local val,result = sensor.ds18b20(ds18b20_pin, true)
        log.info("ds18b20", val,result)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
