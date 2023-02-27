--[[
@module ec11
@summary ec11 编码器驱动(一定一脉冲)
@version 1.0
@date    2023.03.27
@author  Dozingfiretruck
@usage
-- 用法实例
local ec11 = require("ec11")

local GPIO_A = pin.PB02
local GPIO_B = pin.PB05
ec11.init(GPIO_A,GPIO_B)
local count = 0
local function EC11CallBack(direction)
    if direction == "left" then
        count = count - 1
    else
        count = count + 1
    end
    print(direction,count)
end

sys.subscribe("EC11",EC11CallBack)
]]


local ec11 = {}
local sys = require "sys"

local A = false
local B = false

--[[
ec11
@api ec11.init(GPIO_A,GPIO_B)
@number GPIO_A A引脚
@number GPIO_B B引脚
@usage
ec11.init(0)
]]
function ec11.init(GPIO_A,GPIO_B)
    gpio.debounce(GPIO_A, 10)
    gpio.debounce(GPIO_B, 10)

    gpio.setup(GPIO_A, function()
        if B then
            sys.publish("EC11","left")
            A = false
            B = false
        else
            A = true
        end
    end,gpio.PULLUP,gpio.FALLING)

    gpio.setup(GPIO_B, function()
        if A then
            sys.publish("EC11","right")
            A = false
            B = false
        else
            B = true
        end
    end,gpio.PULLUP,gpio.FALLING)
end

return ec11


