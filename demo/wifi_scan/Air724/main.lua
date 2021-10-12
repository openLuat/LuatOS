
PROJECT = "wlandemo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(1800, pmd.LDO_VLCD)

sys.taskInit(function()
    local netled = gpio.setup(1, 0)
    local count = 1
    while 1 do
        netled(1)
        sys.wait(1000)
        netled(0)
        sys.wait(1000)
        log.info("luatos", "hi", count, os.date())
        count = count + 1
    end
end)

sys.subscribe("NET_READY", function ()
    log.info("net", "NET_READY Get!!!")
end)

sys.timerLoopStart(function ()
    wlan.scan()
end, 60000)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
