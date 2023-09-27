
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "at24cdemo"
VERSION = "1.0.0"
-- sys库是标配
sys = require("sys")

--1010 000x
--7bit地址，不包含最后一位读写位
local addr = 0x50
-- 按照实际芯片更改编号哦
local i2cid = 0

sys.taskInit(function()
    log.info("i2c initial",i2c.setup(i2cid))
    while true do
        --当使用芯片为AT24C32及以上时，其地址命令为两个8bit地址，前为地址高八位，后为地址低八位
        i2c.send(i2cid, addr, string.char(0x01, 0x01) .. "12345678")
        sys.wait(100)
        --开始信号 --> 控制命令 -->。->读取数据 -->X --> 停止信号注:。处为等待响应，x为发送非应答;因读取时需要先写入读取地址所以需要先send
        i2c.send(i2cid, addr, string.char(0x01, 0x02))
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
