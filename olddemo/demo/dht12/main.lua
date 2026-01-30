
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dht12"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- https://datasheet.lcsc.com/szlcsc/DHT12-Digital-temperature-and-humidity-sensor_C83989.pdf
-- Air302只有一个i2c, id=0
-- 如果读不到数据, 请尝试以下操作
-- 1. 调换SCL和SDA
-- 2. 确保SCL和SDA均有上拉到VCC(3.3v), 1k~10k

-- -- 初始化并打开I2C操作DHT12
-- local function read_dht12(id)

--     local data = i2c.readReg(id, 0x5C, 0, 5)
--     if not data then
--         log.info("i2c", "read reg fail")
--         return
--     end


--     log.info("DHT12 HEX data: ", data:toHex())
--     -- 分别是湿度整数,湿度小数,温度整数,温度湿度
--     local _, h_H, h_L, t_H, t_L,crc = pack.unpack(data, 'b5')
--     log.info("DHT12 data: ", h_H, h_L, t_H, t_L)
--     -- 计算校验和, 前4位的值相加应该等于最后一位的值
--     if (((h_H + h_L + t_H + t_L) & 0xFF )) ~= crc then
--         log.info("DHT12", "check crc fail")
--         return "0.0", "0.0"
--     end
--     -- 需要考虑温度低于0度的情况, t_L第0位是符号位
--     local t_L2 = tonumber(t_L)
--     if t_L2 > 127 then
--         return h_H .. ".".. h_L, "-" .. t_H .. "." .. tostring(t_L2 - 128)
--     else
--         return h_H .. ".".. h_L, t_H .. "." .. t_L
--     end
-- end

sys.taskInit(function()
    local id = 0--i2c的id，请按需更改
    while 1 do
        sys.wait(5000) -- 5秒读取一次
        i2c.setup(id, i2c.SLOW)
        --log.info("dht12", read_dht12(0)) -- 如果想用传统方式读取,请取消read_dht12方法的注释
        log.info("dht12", i2c.readDHT12(id))
        i2c.close(id)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
