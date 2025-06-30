
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wififota"
VERSION = "1.0.11"

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]

PWR8000S = function(level)
    gpio.set(23, level)
end

gpio.debounce(0, 1000)
gpio.setup(0, function()
    sys.taskInit(function()
        log.info("复位Air8000S")
        PWR8000S(0)
        sys.wait(20)
        PWR8000S(1)
    end)
end, gpio.PULLDOWN)

sys.taskInit(function()
    sys.wait(1000)
    airlink.debug(1)
    airlink.sfota("/luadb/air8000s_v11.bin")
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
