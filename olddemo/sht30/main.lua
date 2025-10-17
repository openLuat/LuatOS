
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sht30demo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")

-- 接线
--[[
SHT30 --- Air302
SDA   -   I2C_SDA
SCL   -   I2C_SCL
VCC   -   VDDIO
GND   -   GND
]]

-- 提示, 老板子上的I2C丝印可能是反的, 如果读取失败请调换一下SDA和SLA

-- 启动个task, 定时查询SHT20的数据
sys.taskInit(function()

    -- sht30的默认i2c地址
    local addr = 0x44
    -- 按实际修改哦
    local id = 0

    log.info("i2c", "initial",i2c.setup(id))

    while true do
        --第一种方式
        i2c.send(id, addr, string.char(0x2C, 0x06))
        sys.wait(5) -- 5ms
        local data = i2c.recv(id, addr, 6)
        log.info("sht30", data:toHex())
        if #data == 6  then
            local _,tval,ccrc,hval,hcrc = pack.unpack(data, ">HbHb")
            -- local cTemp = ((((data:byte(1) * 256.0) + data:byte(2)) * 175) / 65535.0) - 45
            -- local fTemp = (cTemp * 1.8) + 32
            -- local humidity = ((((data:byte(4) * 256.0) + data:byte(5)) * 100) / 65535.0)
            local cTemp = ((tval * 175) / 65535.0) - 45
            -- local fTemp = (cTemp * 1.8) + 32
            local humidity = ((hval * 100) / 65535.0)
            log.info("sht30", cTemp, humidity)
        end
        sys.wait(2000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
