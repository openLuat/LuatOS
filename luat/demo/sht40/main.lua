
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sht40demo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")

-- 接线
--[[
SHT40 --- 模块
SDA   -   I2C_SDA
SCL   -   I2C_SCL
VCC   -   3.3V
GND   -   GND

SHT40手册: https://www.mouser.cn/datasheet/2/682/Datasheet_SHT4x-3003109.pdf
]]


-- 启动个task, 定时查询SHT40的数据
sys.taskInit(function()

    local tmp,hum -- 原始数据
    local temp,hump -- 真实值

    local addr = 0x44
    -- 按实际修改哦
    local id = 0

    log.info("i2c", "initial",i2c.setup(id))

    while 1 do
        sys.wait(400)
        local serial_num = i2c.readReg(addr, 0x89, 6)
        if serial_num and #serial_num ~= 6 then
            break
        end
        log.info("sht40", "尚未检测到设备")
    end

    while true do
        local tmp = i2c.readReg(addr, 0xFD, 6)
        if tmp and #tmp == 6 then
            local _,tval,crc1,hval,crc2 = pack.unpack(tmp,'>HbHb')
            if tval and hval then
                temp = (((17572 * tval) >> 16) - 4685)/100
                hump = (((12500 * hval) >> 16) - 600)/100
                log.info("SHT40", "temp,humi",temp,hump)
            end
        end
        sys.wait(1000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
