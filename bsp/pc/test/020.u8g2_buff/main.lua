
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "httpdemo"
VERSION = "1.0.0"

--[[
本demo需要http库, 大部分能联网的设备都具有这个库
http也是内置库, 无需require
]]

-- sys库是标配
_G.sys = require("sys")
--[[特别注意, 使用http库需要下列语句]]
_G.sysplus = require("sysplus")


sys.taskInit(function()
    sys.wait(100)
    u8g2.begin({ic = "ssd1306",direction = 0,mode="i2c_hw",i2c_id=1,i2c_speed = i2c.FAST})
    u8g2.DrawUTF8("U8g2+LuatOS", 4, 4)
    u8g2.SendBuffer()
    local len = u8g2.CopyBuffer()
    log.info("缓冲区大小", len)
    local buff = zbuff.create(len)
    log.info("zbuff", buff)
    u8g2.CopyBuffer(buff)
    log.info("buff数据", buff:toStr(0, 256):toHex())
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
