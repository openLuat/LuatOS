
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "2712_demo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
充电IC的相关逻辑
]]

local gpio_pin = 152

local sensor_addr = 0x04
local V_ctrl_register = 0x00
local I_ctrl_register = 0x01
local mode_register = 0x02
local config_register = 0x03

local status1_register = 0x05   --read only
local status2_register = 0x06   --read only
local status3_register = 0x07   --read only
local id_register = 0x08        --read only

local set_4V = 0xE0
local set_4V25 = 0x20
local set_4V35 = 0x60
local set_4V45 = 0xA0


gpio.setup(gpio_pin, 1, gpio.PULLUP)
sys.taskInit(function()
    sys.wait(1000)
    local result, data = sensor.yhm27xx(gpio_pin, sensor_addr, id_register)
    sys.wait(200)
    log.info("yhm27xxx", result, data)
    if result == true and data ~= nil then
        log.info("yhm27xxx", "yhm27xx存在--")

        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, sensor_addr, V_ctrl_register)
        log.info("yhm27xxx 0x00 读取数据为：" , data, result)

        -- 写入V_CTRL寄存器 设置成 4.25v
        result = sensor.yhm27xx(gpio_pin, sensor_addr, V_ctrl_register, set_4V25)
        if result == true then
            log.info("yhm27xxx 写入V_CTRL成功：" , data, result)
        else
            log.info("yhm27xxx", "写入V_CTRL失败, ", result)
        end

    else
        log.warn("yhm27xxx", "yhm27xx不存在")
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
