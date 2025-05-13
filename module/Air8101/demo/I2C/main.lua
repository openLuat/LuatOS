
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sht20demo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")
--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

--本demo演示通过I2C协议去读取SHT20温湿度传感器的过程，并介绍luatos中I2C相关接口的用法。
-- 接线
--[[
SHT20 --- 模块
SDA   -   I2C_SDA
SCL   -   I2C_SCL
VCC   -   VDDIO
GND   -   GND
]]

--第一种方式，通过硬件I2C来驱动
-- 启动个task, 定时查询SHT20的数据
sys.taskInit(function()
    local tmp,hum -- 原始数据
    local temp,hump -- 真实值

    --0100 0000  传感器七位地址
    local addr = 0x40
    -- 按实际修改哦
    local id = 0
    ------------------硬件I2C---------------------------------
    log.info("i2c", "initial",i2c.setup(id)) --初始化I2C


    while true do
        i2c.send(id, addr, string.char(0xF3)) --发送0xF3来查询温度
        sys.wait(100)
        tmp = i2c.recv(id, addr, 2)  --读取传感器的温度值
        log.info("SHT20", "read tem data", tmp:toHex())

        i2c.send(id, addr, string.char(0xF5)) --发送0xF5来查询湿度
        sys.wait(100)
        hum = i2c.recv(id, addr, 2)  --读取传感器湿度值
        log.info("SHT20", "read hum data", hum:toHex())
        local _,tval = pack.unpack(tmp,'>H') --提取一个按照大端字节序编码的16位无符号整数
        local _,hval = pack.unpack(hum,'>H')
        log.info("SHT20", "tval hval", tval,hval)
        if tval and hval then
            --按照传感器手册来计算对应的温湿度
            temp = (((17572 * tval) >> 16) - 4685)/100
            hump = (((12500 * hval) >> 16) - 600)/100
            log.info("SHT20", "temp,humi",string.format("%.2f",temp),string.format("%.2f",hump))
        end
        sys.wait(1000)
    end

    ------------------软件I2C---------------------------------
    -- local softI2C = i2c.createSoft(20,21)
    -- while true do
    --     i2c.send(softI2C, addr, string.char(0xF3)) --发送0xF3来查询温度
    --     sys.wait(100)
    --     tmp = i2c.recv(softI2C, addr, 2)  --读取传感器的温度值
    --     log.info("SHT20", "read tem data", tmp:toHex())
    --     i2c.send(softI2C, addr, string.char(0xF5)) --发送0xF5来查询湿度
    --     sys.wait(100)
    --     hum = i2c.recv(softI2C, addr, 2)  --读取传感器湿度值
    --     log.info("SHT20", "read hum data", hum:toHex())
    --     local _,tval = pack.unpack(tmp,'>H') --提取一个按照大端字节序编码的16位无符号整数
    --     local _,hval = pack.unpack(hum,'>H')
    --     log.info("SHT20", "tval hval", tval,hval)
    --     if tval and hval then
    --         --按照传感器手册来计算对应的温湿度
    --         temp = (((17572 * tval) >> 16) - 4685)/100
    --         hump = (((12500 * hval) >> 16) - 600)/100
    --         log.info("SHT20", "temp,humi",string.format("%.2f",temp),string.format("%.2f",hump))
    --     end
    --     sys.wait(1000)
    -- end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
