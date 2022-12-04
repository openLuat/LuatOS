
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "wdtdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")


sys.taskInit(function()
    -- 这个demo要求有wdt库
    -- wdt库的使用,基本上每个demo的头部都有演示
    -- 模组/芯片的内部硬狗, 能解决绝大多数情况下的死机问题
    -- 但如果有要求非常高的场景, 依然建议外挂硬件,然后通过gpio/i2c定时喂狗
    if wdt == nil then
        while 1 do
            sys.wait(1000)
            log.info("wdt", "this demo need wdt lib")
        end
    end
    -- 注意, 大部分芯片/模块是 2 倍超时时间后才会重启
    -- 以下是常规配置, 9秒超时, 3秒喂一次狗
    -- 若软件崩溃,死循环,硬件死机,那么 最多 18 秒后,自动复位
    -- 注意: 软件bug导致业务失败, 并不能通过wdt解决
    wdt.init(9000)
    sys.timerLoopStart(wdt.feed, 3000)
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
