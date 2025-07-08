
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "simdetdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--配置gpio为输入模式，下拉，并会触发中断
--请根据实际需求更改gpio编号和上下拉
--SIMDET配置为34
local gpio_pin = 34
gpio.debounce(gpio_pin, 200, 1)
gpio.setup(gpio_pin, function(val)
	local status = gpio.get(gpio_pin)
    log.info("gpio", "IRQ",gpio_pin, val, status)
	if status == 0 then
		log.info("SIM REMOVE")
		mobile.flymode(0, true)	
	else
		log.info("SIM READY")
		mobile.flymode(0, false)	
	end	
end, gpio.PULLUP) 

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
