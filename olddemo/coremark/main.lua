
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "coremark"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

--添加硬狗防止程序卡死
--wdt.init(9000)--初始化watchdog设置为9s
--sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗

sys.taskInit(function()
    sys.wait(2000)
    if coremark then
        if mcu and (rtos.bsp():lower() == "air101" or rtos.bsp():lower() == "air103") then
            mcu.setClk(240)
        end
        log.info("coremark", "G0-----------------------------")
        coremark.run()
        log.info("coremark", "Done---------------------------")
    else
        log.info("coremark", "need coremark lib")
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
