--本demo演示虚拟IO操作，目前有WAKEUP0~5,CHG_DET,PWR_KEY，具体有哪些IO见对应芯片模块的说明
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "virtualio_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

local function wakeup(io)
	log.info("wakeup", io, "input level", gpio.get(io))
end

if gpio.PWR_KEY then
    gpio.setup(gpio.PWR_KEY, function() 
        log.info("pwrkey", gpio.get(gpio.PWR_KEY))
    end, gpio.PULLUP)
else
    log.info("bsp not support powerkey")
end

if gpio.CHG_DET then
    gpio.setup(gpio.CHG_DET, function() 
        log.info("charge detect", gpio.get(gpio.CHG_DET))
    end, gpio.PULLUP)
else
    log.info("bsp not support charge detect")
end

if gpio.WAKEUP0 then
    gpio.setup(gpio.WAKEUP0, wakeup, gpio.PULLUP)
else
    log.info("bsp not support WAKEUP0")
end

if gpio.WAKEUP1 then
    gpio.setup(gpio.WAKEUP1, wakeup, gpio.PULLUP)
else
    log.info("bsp not support WAKEUP1")
end

if gpio.WAKEUP2 then
    gpio.setup(gpio.WAKEUP2, wakeup, gpio.PULLUP)
else
    log.info("bsp not support WAKEUP2")
end

if gpio.WAKEUP3 then
    gpio.setup(gpio.WAKEUP3, wakeup, gpio.PULLUP)
else
    log.info("bsp not support WAKEUP3")
end

if gpio.WAKEUP4 then
    gpio.setup(gpio.WAKEUP4, wakeup, gpio.PULLUP)
else
    log.info("bsp not support WAKEUP4")
end

if gpio.WAKEUP5 then
    gpio.setup(gpio.WAKEUP5, wakeup, gpio.PULLUP)
else
    log.info("bsp not support WAKEUP5")
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
