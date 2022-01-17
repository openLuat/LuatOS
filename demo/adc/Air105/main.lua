
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "adcdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
local sys = require "sys"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

sys.taskInit(function()
    while 1 do
        adc.open(0) -- 模块上的ADC0脚-PA1, 0~2.4v,不要超过范围使用!!!
        adc.open(1) -- 模块上的ADC1脚-PA4, 0~2.4v,不要超过范围使用!!!
        sys.wait(500)
        log.debug("adc", "adc0", adc.read(0))
        log.debug("adc", "adc1", adc.read(1))
        -- 使用完毕后关闭,可以使得休眠电流更低.
        adc.close(0)
        adc.close(1)
        sys.wait(500)
    end
    
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
