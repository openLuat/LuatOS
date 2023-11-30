
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "usb_connect_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

local rtos_bsp = rtos.bsp()

local function pinx()
    if rtos_bsp == "EC618" then -- AIR780E                          -- 33是虚拟GPIO，见https://wiki.luatos.com/chips/air780e/iomux.html#id1
        return 24, 33           
    elseif rtos_bsp == "EC718P" then -- AIR780EP                    -- 40是虚拟GPIO
        return 27, 40
    else
        return 255, 255
    end
end


local led_pin, vbus_pin = pinx()                                    -- 赋值led，vbus引脚编号

if led_pin ~= 255 and vbus_pin ~= 255 then
    local led = gpio.setup(led_pin, 1) --如果真的把USB拔出，可能无法打印出信息，所以拿个IO输出和USB一样状态的电平
    led(gpio.get(vbus_pin)) --IO输出和USB一样的状态
    gpio.setup(vbus_pin, function() 
        log.info("usb", gpio.get(vbus_pin))
        led(gpio.get(vbus_pin))   --IO输出和USB一样的状态
    end, gpio.PULLUP, gpio.BOTH)
    gpio.debounce(vbus_pin, 500, 1)  --加入消抖是为了尽量能看到输出
    log.info("usb", gpio.get(vbus_pin))
else
    log.info("bsp not support") 
end

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
