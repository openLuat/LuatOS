
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "i2cdemo"
VERSION = "1.0.0"

-- 一定要添加sys.lua !!!!
local sys = require "sys"
--初始化i2c，air101使用id为1
if i2c.setup(0, i2c.FAST, 0x44) == 1 then
    log.info("存在 i2c0")
else
    i2c.close(0) -- 关掉
end
sys.taskInit(function()
    wdt.init(15000)
    sys.timerLoopStart(wdt.feed, 10000)
    while 1 do
        local w = i2c.send(0, 0x44, string.char(0x2c, 0x06)) -- 发送单次采集命令
        sys.wait(10) -- 等待采集
        local r = i2c.recv(0, 0x44, 6) -- 读取数据采集结果
        log.info("recv",r:toHex())
        local a, b, c, d, e, f, g = string.unpack("BBBBBB",r)
        log.info("a",a, b, c, d, e, f, g)
        t = ((4375 * (a * 256 + b)) / 16384) - 4500 --根据SHT30传感器手册给的公式计算温度和湿度
        h = ((2500 * (d * 256 + e)) / 16384)
        log.warn("这里是温度", t/100) -- 打印温度
        log.warn("这里是湿度", h/100) -- 打印湿度
        sys.wait(1000)
    end
    
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
