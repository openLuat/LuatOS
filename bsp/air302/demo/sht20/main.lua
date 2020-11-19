
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sht20demo"
VERSION = "1.0.0"

-- sys库是标配
local sys = require "sys"

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
    -- 当前仅支持i2c0哦
    local id = 0

    log.info("i2c", "initial",i2c.setup(0))

    while true do
        --第一种方式
        i2c.send(id, addr, string.char(0xe3))
        tmp = i2c.recv(id, addr, 2)
        log.info("SHT20", "read tem data", tmp:toHex())

        i2c.send(id, addr, string.char(0xe5))
        hum = i2c.recv(id, addr, 2)
        log.info("SHT20", "read hum data", hum:toHex())
        local _,tval = pack.unpack(tmp,'>H')
        local _,hval = pack.unpack(hum,'>H')
        if tval and hval then
            temp = ((1750*(tval)/65535-450))/10
            hump = ((1000*(hval)/65535))/10
            log.info("SHT20", "temp,humi",temp,hump)
        end
        sys.wait(1000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
