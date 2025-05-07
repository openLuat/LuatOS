
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "power_on_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

local powerkey_pin = 46    -- 赋值powerkey引脚编号

-- local count=0    -- 五秒内短按三次关机
-- local function pwrkeycb() 
--     log.info("pwrkey", gpio.get(powerkey_pin))
--     if gpio.get(powerkey_pin) == 0 then
--         count=count+1
--         sys.timerStart(function()
--             log.info("计数归零")
--             count=0
--         end, 5000)
--         if count>=3 then
--             pm.shutdown() 
--         end
--     end
-- end

function pwroff()
    log.info("power off!!")
    pm.shutdown() 
end

local function pwrkeycb()    --长按五秒关机
    log.info("pwrkey", gpio.get(powerkey_pin))
    if gpio.get(powerkey_pin) == 1 then
        sys.timerStop(pwroff)
    else
        sys.timerStart(pwroff, 5000)
    end
end

if powerkey_pin ~= 255 then
    gpio.setup(powerkey_pin, pwrkeycb, gpio.PULLUP,gpio.BOTH)
else
    log.info("bsp not support")
end
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
