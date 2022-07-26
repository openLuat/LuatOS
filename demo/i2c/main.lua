
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "i2c 24c02 demo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")

--1010 000x
--7bit地址，不包含最后一位读写位
local addr = 0x50
-- 按照实际芯片更改编号哦
local i2cid = 0

sys.taskInit(function()
    log.info("i2c initial",i2c.setup(0))
    while true do
        --第一种方式
        i2c.send(i2cid, addr, string.char(0x01).."1234abcd")
        sys.wait(100)
        i2c.send(i2cid, addr, string.char(0x01))
        local data = i2c.recv(i2cid, addr, 8)
        log.info("i2c", "data1",data:toHex(),data)

        --第二种方式
        i2c.writeReg(i2cid, addr, 0x01, "abcd1234")
        sys.wait(100)
        local data = i2c.readReg(i2cid, addr, 0x01, 8)
        log.info("i2c", "data2",data:toHex(),data)
        sys.wait(1000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
