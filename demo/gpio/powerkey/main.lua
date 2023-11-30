
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pwrkey_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

local rtos_bsp = rtos.bsp()

local function pinx()
    if rtos_bsp == "EC618" then -- AIR780E                          -- 35是虚拟GPIO，见https://wiki.luatos.com/chips/air780e/iomux.html#id1
        return 35           
    elseif rtos_bsp == "EC718P" then -- AIR780EP                    -- 46是虚拟GPIO
        return 46
    else
        return 255 
    end
end


local powerkey_pin = pinx()                                         -- 赋值powerkey引脚编号

if powerkey_pin ~= 255 then
    gpio.setup(powerkey_pin, function() 
        log.info("pwrkey", gpio.get(powerkey_pin))
    end, gpio.PULLUP)
else
    log.info("bsp not support")
end


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
