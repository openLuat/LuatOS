-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "aht10demo"
VERSION = "1.0.0"

-- sys库是标配
local sys = require "sys"

pmd.ldoset(3300, pmd.LDO_VIBR)


-- 接线
--[[
AHT10 --- Air724
SDA   -   I2C2_SDA (GPIO_15)
SCL   -   I2C2_SCL (GPIO_14)
VCC   -   3.3V
GND   -   GND
]]

sys.taskInit(function()
    local tag = "I2C.aht10"
    sys.wait(5000)
    -- aht10的默认i2c地址 0x38
    local i2c_device_addr = 0x38

    -- 连接至I2C2
    local i2c_id = 2

    if i2c.exist(i2c_id) then
        log.info(tag .. ".init", "SUCCESS")
        if i2c.setup(i2c_id, i2c.FAST, i2c_device_addr) == 1 then
            log.info(tag .. ".setup", "SUCCESS")
            while true do
                if i2c.send(i2c_id, i2c_device_addr, string.char(0xac, 0x22, 0x00)) then
                    sys.wait(1000)
                    local receivedData = i2c.recv(i2c_id, i2c_device_addr, 6)
                        if #receivedData == 6 then
                            log.info(tag .. ".receivedDataHex", receivedData:toHex())
                            local tempBit = string.byte(receivedData, 6) + 0x100 * string.byte(receivedData, 5) + 0x10000 * (string.byte(receivedData, 4) & 0x0F)
                            local humidityBit = (string.byte(receivedData, 4) & 0xF0) + 0x100 * string.byte(receivedData, 3) + 0x10000 * string.byte(receivedData, 2)  
                            humidityBit = humidityBit >> 4
                            log.info(tag .. ".tempBit", tempBit)
                            log.info(tag .. ".humidityBit", humidityBit)
                            local calcTemp = (tempBit / 1048576) * 200 - 50
                            local calcHum = humidityBit / 1048576
                            log.info(tag .. ".calcTemp", calcTemp)
                            log.info(tag .. ".calcHum", calcHum)
                            log.info(tag .. ".当前温度", string.format("%.1f℃", calcTemp))
                            log.info(tag .. ".当前湿度", string.format("%.1f%%", calcHum * 100))
                            sys.wait(1000)
                        else
                            log.error(tag .. ".receive", "FAIL")
                        end
                else
                    log.error(tag .. ".send", "FAIL")
                end
            end
        else
            log.error(tag .. ".setup", "FAIL")
        end
    else
        log.error("I2C.aht10", "I2C 2 通道不存在")
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
