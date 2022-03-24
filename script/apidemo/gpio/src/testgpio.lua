local testgpio = {}

local sys = require "sys"

local LEDA
local LEDB
local LEDC

--下面的GPIO引脚编号，请根据实际需要进行更改！
-- Air101开发板的3个LED分别为 PB08/PB09/PB10
-- Air103开发板的3个LED分别为 PB24/PB25/PB26
-- Air105开发板的3个LED分别为 PD14/PD15/PC03
if rtos.bsp() == "air101" then -- 与w800/805等价
    LEDA = gpio.setup(pin.PB08, 0, gpio.PULLUP)
    LEDB = gpio.setup(pin.PB09, 0, gpio.PULLUP)
    LEDC = gpio.setup(pin.PB10, 0, gpio.PULLUP)
elseif rtos.bsp() == "air103" then -- 与w806等价
    LEDA = gpio.setup(pin.PB24, 0, gpio.PULLUP)
    LEDB = gpio.setup(pin.PB25, 0, gpio.PULLUP)
    LEDC = gpio.setup(pin.PB26, 0, gpio.PULLUP)
elseif rtos.bsp() == "air105" then 
    LEDA = gpio.setup(pin.PD14, 0, gpio.PULLUP)
    LEDB = gpio.setup(pin.PD15, 0, gpio.PULLUP)
    LEDC = gpio.setup(pin.PC03, 0, gpio.PULLUP)
end

sys.taskInit(function()
    local count = 0
    while 1 do
        sys.wait(500)
        -- 一闪一闪亮晶晶
        LEDA(count % 3 == 0 and 1 or 0)
        LEDB(count % 3 == 1 and 1 or 0)
        LEDC(count % 3 == 2 and 1 or 0)
        log.info("gpio", "Go Go Go", count, rtos.bsp())
        count = count + 1
    end
end)

return testgpio