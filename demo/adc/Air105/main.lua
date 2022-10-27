
-- LuaTools需要PROJECT和VERSION这两个信息
-- air105 adc参考电压是1.88V，所有通道一致，
-- 内部分压没有隔离措施，在开启内部分压后，量程有所变化，具体看寄存器手册，1~5分压后能测到3.6，6通道能接近5V，但是不能直接测5V，可以测4.2V
-- 0通道是始终开启无法关闭分压。
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
    adc.setRange(adc.ADC_RANGE_3_6) --开启的内部分压，可以把量程扩大
    adc.open(0) -- 0通道是内部采集CHARGE_VBAT, 0~5v, 这是特别的
    adc.open(5) 
    adc.open(6) 
    while 1 do
        log.debug("adc", "adc0", adc.read(0))
        log.debug("adc", "adc5", adc.read(5))
        log.debug("adc", "adc6", adc.read(6))
        sys.wait(500)
    end
    adc.close(0)
    adc.close(5)
    adc.close(6)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
