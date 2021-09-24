-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "SI7021"
VERSION = "1.0.0"
local i2cId = 0
-- 一定要添加sys.lua !!!!
local sys = require "sys"

--添加硬狗防止程序卡死
wdt.init(15000)--初始化watchdog设置为15s
sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗

sys.taskInit(function()
    wdt.init(15000)
    sys.timerLoopStart(wdt.feed, 10000)
    sys.wait(5000)
    if i2c.setup(i2cId, i2c.FAST, 0x40) == 1 then
        log.info("存在 i2c0")
    else
        i2c.close(i2cId) -- 关掉
    end
    while true do
        local temp, humi
        i2c.send(i2cId, 0x40, string.char(0xF3))
        sys.wait(200)

        local rawTemp = i2c.recv(i2cId, 0x40, 3)
        log.info("temp_tohex", rawTemp:toHex())
        local temp_h, temp_l = string.byte(rawTemp, 1), string.byte(rawTemp, 2)
        if temp_h and temp_l then
            temp = temp_h * 256 + temp_l
            temp = ((175.72 * temp) / 65536) - 46.85
        else
            log.info("没温度")
        end

        sys.wait(200)

        i2c.send(i2cId, 0x40, string.char(0xF5))
        sys.wait(200)
        local rawHumi = i2c.recv(i2cId, 0x40, 3)
        log.info("raw_tohex", rawHumi:toHex())
        local humi_h, humi_l = rawHumi:byte(1), rawHumi:byte(2)
        if humi_h and humi_l then
            humi = humi_h * 256 + humi_l
            humi = ((125 * humi) / 65536) - 6
        else
            log.info("没湿度")
        end

        if temp and humi then
            log.info("测量数据", "温度:", temp - temp % 0.01 .. "°C",
                     "湿度:", humi - humi % 0.01 .. "%RH")
        else
            log.info("没测量数据")
        end
        sys.wait(200)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
