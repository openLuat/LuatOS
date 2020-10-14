
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mytemp"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- 硬件接线
--[[
GPIO17     -- DAT
VPAD/VDDIO -- VCC
GND        -- GND
]]


NETLED = gpio.setup(19, 1)
sys.taskInit(function()
    while 1 do
        -- 一闪一闪亮晶晶
        NETLED(0)
        sys.wait(500)
        NETLED(1)
        sys.wait(500)
    end
end)


sys.taskInit(function()
    while 1 do
        sys.wait(5000) -- 5秒读取一次
        log.info("sensor", "ds18b20", sensor.ds18b20(17)) -- GPIO17脚
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
