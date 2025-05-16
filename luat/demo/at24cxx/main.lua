
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "at24cdemo"
VERSION = "1.0.0"
-- sys库是标配
sys = require("sys")


--经过测试，该demo对相同引脚的一些Flash同样支持  
--目前测试发现的Flash型号：FM24CL64-GTR

--1010 000x
--7bit地址，不包含最后一位读写位
local addr = 0x50
-- 按照实际芯片更改编号哦
local i2cid = 0

sys.taskInit(function()
    log.info("i2c initial",i2c.setup(i2cid))
    while true do
        i2c.send(i2cid, addr, string.char(0x01, 0x00) .. "12345678")
        sys.wait(100)
        i2c.send(i2cid, addr, string.char(0x01, 0x00))
        sys.wait(100)
        local data = i2c.recv(i2cid, addr, 8)
        log.info("i2c", "data2", data:toHex(), #data)
        sys.wait(1000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
