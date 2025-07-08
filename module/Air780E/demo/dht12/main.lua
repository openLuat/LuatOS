
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dht12"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- https://datasheet.lcsc.com/szlcsc/DHT12-Digital-temperature-and-humidity-sensor_C83989.pdf

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
