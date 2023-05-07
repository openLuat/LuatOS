
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sht20demo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")

-- 接线
--[[
SHT20 --- Air302
SDA   -   I2C_SDA
SCL   -   I2C_SCL
VCC   -   VDDIO
GND   -   GND
]]

-- 提示, 老板子上的I2C丝印可能是反的, 如果读取失败请调换一下SDA和SLA

-- 启动个task, 定时查询SHT20的数据
sys.taskInit(function()

    local tmp,hum -- 原始数据
    local temp,hump -- 真实值

    --1010 000x
    local addr = 0x40
    -- 按实际修改哦
    local id = 0

    log.info("i2c", "initial",i2c.setup(id))

    while true do
        --第一种方式
        i2c.send(id, addr, string.char(0xF3))
        sys.wait(100)
        tmp = i2c.recv(id, addr, 2)
        log.info("SHT20", "read tem data", tmp:toHex())

        i2c.send(id, addr, string.char(0xF5))
        sys.wait(100)
        hum = i2c.recv(id, addr, 2)
        log.info("SHT20", "read hum data", hum:toHex())
        local _,tval = pack.unpack(tmp,'>H')
        local _,hval = pack.unpack(hum,'>H')
        if tval and hval then
            temp = (((17572 * tval) >> 16) - 4685)/100
            hump = (((12500 * hval) >> 16) - 600)/100
            log.info("SHT20", "temp,humi",temp,hump)
        end
        sys.wait(1000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
