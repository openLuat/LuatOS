
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "2712_demo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--[[
充电IC的相关逻辑
]]

local gpio_pin = 24
gpio.setup(gpio_pin, 1, gpio.PULLUP)
sys.taskInit(function()
    sys.wait(1000)
    local result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x08)
    sys.wait(200)
    log.info("yhm27xxx", result, data)
    if result == true and data ~= nil then
        log.info("yhm27xxx", "yhm27xx存在--")

        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x00)
        log.info("yhm27xxx 0x00 读取数据为：" , data, result)

        -- 写入V_CTRL寄存器 设置成 4.25v
        result = sensor.yhm27xx(gpio_pin, 0x04, 0x00, 0x20)
        if result == true then
            sys.wait(200)
            result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x00)
            log.info("yhm27xxx 写入V_CTRL成功：" , data, result)
        else
            log.info("yhm27xxx", "写入V_CTRL失败, ", result)
        end

        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x01)
        log.info("yhm27xxx 0x01 读取数据为：" , data, result)
        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x02)
        log.info("yhm27xxx 0x02 读取数据为：" , data, result)
        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x03)
        log.info("yhm27xxx 0x03 读取数据为：" , data, result)
        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x04)
        log.info("yhm27xxx 0x04 读取数据为：" , data, result)
        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x05)
        log.info("yhm27xxx 0x05 读取数据为：" , data, result)
        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x06)
        log.info("yhm27xxx 0x06 读取数据为：" , data, result)
        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x07)
        log.info("yhm27xxx 0x07 读取数据为：" , data, result)
        sys.wait(200)
        result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x08)
        log.info("yhm27xxx 0x08 读取数据为：" , data, result)

    else
        log.warn("yhm27xxx", "yhm27xx不存在")
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
