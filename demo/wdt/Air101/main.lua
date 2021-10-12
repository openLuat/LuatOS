
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wdtdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

wdt.init(10000)
sys.timerLoopStart(wdt.feed, 3000)

sys.taskInit(function()
    sys.wait(5000)
    sys.setTimeout(5000)
    while 1 do
        sys.wait(500)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
