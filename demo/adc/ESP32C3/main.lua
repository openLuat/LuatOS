
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "adcdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    while 1 do
        adc.open(0) -- 模块上的ADC0脚
        adc.open(1) -- 模块上的ADC1脚
        adc.open(2) -- 模块上的ADC2脚
        adc.open(3) -- 模块上的ADC3脚
        adc.open(4) -- 模块上的ADC4脚
        adc.open(10) -- CPU温度
        sys.wait(500)
        log.debug("adc", "adc0", adc.read(0))
        log.debug("adc", "adc1", adc.read(1))
        log.debug("adc", "adc2", adc.read(2))
        log.debug("adc", "adc3", adc.read(3))
        log.debug("adc", "adc4", adc.read(4))
        log.debug("adc", "adc_temp", adc.read(10))
        adc.close(0)
        adc.close(1)
        adc.close(2)
        adc.close(3)
        adc.close(4)
        adc.close(10)
        sys.wait(500)
    end

end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
