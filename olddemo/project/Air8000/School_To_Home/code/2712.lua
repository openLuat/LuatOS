--[[
充电IC的相关逻辑
]]

local gpio_pin = pcb.chargeCmdPin()
gpio.setup(gpio_pin, 1, gpio.PULLUP)
sys.taskInit(function()
    sys.wait(1000)
    local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x08)
    sys.wait(200)
    log.info("yhm27xxx", result, data)
    if result == true and data ~= nil then
        log.info("yhm27xxx", "yhm27xx存在--")
        sys.wait(200)
        result = yhm27xx.cmd(gpio_pin, 0x04, 0x01, 0x02)
        if result == true then
            result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x01, 0x02)
            if result then
                log.info("yhm27xxx", "写入I_CTRL成功")
            else
                log.info("yhm27xxx", "测试I_CTRL失败")
            end
        else
            log.info("yhm27xxx", "读取失败", result)
        end
        local result = yhm27xx.cmd(gpio_pin, 0x04, 0x00, 0x00)
        if result == true then
            result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x00, 0x00)
            if result then
                log.info("yhm27xxx", "写入V_CTRL成功")
            else
                log.info("yhm27xxx", "测试V_CTRL失败")
            end
        else
            log.info("yhm27xxx", "读取失败", result)
        end
    else
        log.warn("yhm27xxx", "yhm27xx不存在")
    end
end)
