--[[
充电IC的相关逻辑
]]

local gpio_pin = pcb.chargeCmdPin()
gpio.setup(gpio_pin, 1, gpio.PULLUP)
sys.taskInit(function()
    sys.wait(1000)
    local result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x08)
    sys.wait(200)
    log.info("yhm27xxx", result, data)
    if result == true and data ~= nil then
        log.info("yhm27xxx", "yhm27xx存在--")
        sys.wait(200)
        result = sensor.yhm27xx(gpio_pin, 0x04, 0x01, 0x02)
        if result == true then
            result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x01)
            if data ~= 2 then
                log.info("yhm27xxx", "写入失败", data)
            else
                log.info("yhm27xxx", "测试成功", data)
            end
        else
            log.info("yhm27xxx", "读取失败", result)
        end
        result = sensor.yhm27xx(gpio_pin, 0x04, 0x00, 0x00)
        if result == true then
            result, data = sensor.yhm27xx(gpio_pin, 0x04, 0x00)
            if data ~= 0 then
                log.info("yhm27xxx", "写入V_CTRL失败, " .. data )
            else
                log.info("yhm27xxx", "测试V_CTRL成功, " .. data, result)
            end
        else
            log.info("yhm27xxx", "读取失败", result)
        end
    else
        log.warn("yhm27xxx", "yhm27xx不存在")
    end
end)
