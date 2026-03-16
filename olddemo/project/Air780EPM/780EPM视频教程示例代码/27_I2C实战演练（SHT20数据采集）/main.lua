-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sht20demo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")
pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)

--[[ mcu.altfun(mcu.I2C, 0, 66, 2, nil)
mcu.altfun(mcu.I2C, 0, 67, 2, nil) ]] 

gpio.setup(2,1)--GPIO2打开给camera_3.3V供电
-- 接线
--[[
SHT20 --- 模块
SDA   -   I2C_SDA
SCL   -   I2C_SCL
VCC   -   VDDIO
GND   -   GND
]]

-- 启动个task, 定时查询SHT20的数据
sys.taskInit(function()

    local tmp,hum -- 原始数据
    local temp,hump -- 真实值

    --1010 000x
    local addr = 0x40
    -- 按实际修改哦
    local id = 1

    log.info("i2c", "initial",i2c.setup(id))
    --i2c.scan()
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
-- 启动个task, 定时查询SHT40测试代码的数据
--[[ sys.taskInit(function()
    local tmp,hum -- 原始数据
    local temp,hump -- 真实值

    --1010 000x
    local addr = 0x44
    -- 按实际修改哦
    local id = 0

    log.info("i2c", "initial",i2c.setup(id))
    --i2c.scan()
    while true do
        --第一种方式
        local resalt=i2c.send(id, addr, string.char(0x89))
        log.info("打印状态=", resalt)
        sys.wait(100)
        tmp = i2c.recv(id, addr, 6)
        log.info("MT6701", "read 03 data", tmp:toHex())

        i2c.send(id, addr, string.char(0x04))
        sys.wait(100)
        hum = i2c.recv(id, addr, 2)
        log.info("MT6701", "read 04 data", hum:toHex())
        local _,tval = pack.unpack(tmp,'>H')
        local _,hval = pack.unpack(hum,'>H')
        if tval and hval then
            temp = (((17572 * tval) >> 16) - 4685)/100
            hump = (((12500 * hval) >> 16) - 600)/100
            log.info("MT6701", "03,04",temp,hump)
        end 
        sys.wait(1000)
    end

end) ]]
-- 启动个task, 定时查询MT6701的数据
--[[ sys.taskInit(function()
    local tmp,hum -- 原始数据
    local temp,hump -- 真实值

    --1010 000x
    local addr = 0x06
    -- 按实际修改哦
    local id = 1

    log.info("i2c", "initial",i2c.setup(id))
    --i2c.scan()
    while true do
        --第一种方式
        local resalt=i2c.send(id, addr, string.char(0x03))
        log.info("打印状态1=", resalt)
        local resalt=i2c.send(id, addr, string.char(0x03))
        log.info("打印状态2=", resalt)
        sys.wait(100)
        tmp = i2c.recv(id, addr, 2)--tmp是字符串
        log.info("MT6701", "read 03 data", tmp:toHex())
        i2c.send(id, addr, string.char(0x04))
        sys.wait(100)
        hum = i2c.recv(id, addr, 2)
        log.info("MT6701", "read 04 data", hum:toHex())
        --local raw_value =(tmp << 6) | (hum & 0x3F)
        -- 步骤4: 转换为角度（0~360°）
        
        
 
        local _,tval = pack.unpack(tmp,'>H')
        log.info("MT6701", "tval=",tval)
        local _,hval = pack.unpack(hum,'>H')
        log.info("MT6701", "hval=",hval)
        if tval and hval then
            --temp = ((tval & 0x00ff) << 8) | ((hval & 0x00fc)>>2)
            --temp = (tval << 6) | (hval & 0x3F)
            temp = (tval >> 2)
            log.info("MT6701", "temp=",temp)
            local angle = (temp / 16383) * 360
            log.info("MT6701", "angle=",angle)
        end 
        sys.wait(5000)
    end

end) ]]

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!