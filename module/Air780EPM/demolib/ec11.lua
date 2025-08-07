--[[
@module ec11
@summary ec11 旋转编码器
@version 1.0
@date    2023.03.27
@author  Dozingfiretruck
@usage
-- 用法实例, 当前支持一定一脉冲
local ec11 = require("ec11")

-- 按实际接线写
local GPIO_A = 6
local GPIO_B = 7
ec11.init(GPIO_A,GPIO_B)

-- 演示接收旋转效果
local count = 0
local function ec11_callBack(direction)
    if direction == "left" then
        -- 往左选,逆时针
        count = count - 1
    else
        -- 往右旋,顺时针
        count = count + 1
    end
    log.info("ec11", direction, count)
end

sys.subscribe("ec11",ec11_callBack)
]]


local ec11 = {}
local sys = require "sys"

local A = false
local B = false

--[[
初始化ec11
@api ec11.init(GPIO_A,GPIO_B)
@number GPIO_A A引脚对应的GPIO编号, 例如 GPIO6, 就写6
@number GPIO_B B引脚对应的GPIO编号, 例如 GPIO7, 就写7
@usage
ec11.init(6,7)
]]
function ec11.init(GPIO_A,GPIO_B)
    gpio.debounce(GPIO_A, 10)
    gpio.debounce(GPIO_B, 10)

    gpio.setup(GPIO_A, function()
        if B then
            sys.publish("ec11","left")
            A = false
            B = false
        else
            A = true
        end
    end,gpio.PULLUP,gpio.FALLING)

    gpio.setup(GPIO_B, function()
        if A then
            sys.publish("ec11","right")
            A = false
            B = false
        else
            B = true
        end
    end,gpio.PULLUP,gpio.FALLING)
end

return ec11


