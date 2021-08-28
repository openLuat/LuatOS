
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

local LEDA = gpio.setup(24, 0, gpio.PULLUP) -- PB1输出模式
local LEDB = gpio.setup(25, 0, gpio.PULLUP) -- PB1输出模式
local LEDC = gpio.setup(26, 0, gpio.PULLUP) -- PB1输出模式

sys.taskInit(function()
    local count = 0
    while 1 do
        -- 一闪一闪亮晶晶
        if (count % 3) == 0 then
            LEDA(1)
            LEDB(0)
            LEDC(0)
        elseif (count % 3) == 1 then
            LEDA(0)
            LEDB(1)
            LEDC(0)
        else
            LEDA(0)
            LEDB(0)
            LEDC(1)
        end
        log.info("gpio", "Go Go Go")
        sys.wait(500)
        count = count + 1
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
