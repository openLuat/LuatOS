
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mytemp"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- 硬件接线
--[[
PB8     -- DAT
VPAD/VDDIO -- VCC
GND        -- GND
]]

sys.taskInit(function()
    while 1 do
        sys.wait(5000) -- 5秒读取一次
        log.info("sensor", "ds18b20", sensor.ds18b20(28)) -- PB8
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
