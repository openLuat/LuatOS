-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

wdt.init(8000)
sys.timerLoopStart(wdt.feed, 3000)
sys.timerLoopStart(log.info, 1000, "say hi")

sys.taskInit(function()
    gpio.debounce(24, 1000)
    sys.wait(1000)
    gpio.setup(24, function()
       log.info("main", "GPIO24中断") 
    end, gpio.PULLUP)
    log.info("main", "3秒后休眠")
    sys.wait(3000)
    pm.wakeupPin(24, 0)
    wdt.close()
    log.info("开始休眠, 定时器唤醒15秒")
    -- pm.dtimerStart(1, 15*1000)
    pm.request(pm.LIGHT)
end)

-- API文档 https://wiki.luatos.com/api/gpio.html

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
