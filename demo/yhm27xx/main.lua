
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "charge"
VERSION = "1.0.0"

sys = require("sys")
log.info("main", PROJECT, VERSION)

--[[
充电IC的相关逻辑
]] local gpio_pin = 15 -- 
-- gpio.setup(gpio_pin, 1, gpio.PULLUP)
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
            result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x01)
            if data ~= 2 then
                log.info("yhm27xxx", "写入失败", data)
            else
                log.info("yhm27xxx", "测试成功", data)
            end
        else
            log.info("yhm27xxx", "读取失败", result)
        end

        log.info("开始读所有寄存器的值")
        table_reg = {0x01, 0x02, 0x03, 0x04, 0x05, 0x05, 0x06, 0x07, 0x08}

        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x00)
        if result then
            log.info("00寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("00寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x01)
        if result then
            log.info("01寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("01寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x02)
        if result then
            log.info("02寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("02寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x03)
        if result then
            log.info("03寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("03寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x04)
        if result then
            log.info("04寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("04寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x05)
        if result then
            log.info("05寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("05寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x06)
        if result then
            log.info("06寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("06寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x07)
        if result then
            log.info("07寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("07寄存器没读到")
        end
        local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x08)
        if result then
            log.info("08寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("08寄存器没读到")
        end
        log.info("等待10S后修改01寄存器的值为0x07<<5")
        sys.wait(10*1000)
        result = yhm27xx.cmd(gpio_pin, 0x04, 0x01, 0x07 << 5)

        if result == true then
            log.info("修改01寄存器成功")
            local result, data = yhm27xx.cmd(gpio_pin, 0x04, 0x01)
            log.info("让我看看现在01寄存器的值", string.format("Value: 0x%02X", data))
        else
            log.info("修改01寄存器失败")
        end
        log.info("等待10s后修改")
        sys.wait(10 * 1000)

    else
        log.warn("yhm27xx", "yhm27xx不存在")
    end
end)

-- result = yhm27xx.cmd(gpio_pin, 0x04, 0x00, 0x08)

sys.run()
