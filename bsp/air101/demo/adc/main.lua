
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "adcdemo"
VERSION = "1.0.0"

-- 一定要添加sys.lua !!!!
local sys = require "sys"

--添加硬狗防止程序卡死
wdt.init(15000)--初始化watchdog设置为15s
sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗

--灯 PB1,
local NETLED = gpio.setup(17, 0)     -- 初始化PB1, 并设置为低电平



sys.taskInit(function()
    wdt.init(15000)
    sys.timerLoopStart(wdt.feed, 10000)
    while 1 do
        log.info("LED", "Go Go Go")
        NETLED(0) -- 低电平,熄灭
        sys.wait(1000)
        NETLED(1) -- 高电平,亮起
        sys.wait(1000)

        adc.open(0) -- 模块上的ADC0脚-PA1, 0~2.4v,不要超过范围使用!!!
        adc.open(1) -- 模块上的ADC1脚-PA4, 0~2.4v,不要超过范围使用!!!
        adc.open(10) -- CPU温度
        --sys.wait(50)

        log.debug("adc", "adc0", adc.read(0))
        log.debug("adc", "adc1", adc.read(1))
        log.debug("adc", "adc_temp", adc.read(10))

        -- 使用完毕后关闭,可以使得休眠电流更低.
        adc.close(0)
        adc.close(1)
        adc.close(10)
    end
    
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
