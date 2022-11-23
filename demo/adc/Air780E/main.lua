-- LuaTools需要PROJECT和VERSION这两个信息
-- Air780E内部ADC接口为12bits 外部直流分压为0-3.4V
-- Air780E内部具有2个ADC接口，ADC0 -- AIO3 ADC1 -- AIO4 
-- Temp -- 10 VBAT -- 11
PROJECT = "adcdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

sys.taskInit(function()
    adc.open(0)
    adc.open(1)
    adc.open(10) -- Temp ADC接口
    adc.open(11) -- VBAT ADC 接口
    while 1 do
        log.debug("adc", "adc0", adc.read(0))
        log.debug("adc", "adc1", adc.read(1))
        log.debug("adc", "adc10", adc.read(10))
        log.debug("adc", "adc11", adc.read(11))
        sys.wait(500)
    end
    adc.close(0)
    adc.close(1)
    adc.close(10)
    adc.close(11)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
