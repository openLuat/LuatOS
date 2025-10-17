
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dht12"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    local dht11_pin = 7
    while 1 do
        sys.wait(1000)
        local h,t,r = sensor.dht1x(dht11_pin, true)
        log.info("dht11", "湿度", h/100, "温度", t/100,r)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
