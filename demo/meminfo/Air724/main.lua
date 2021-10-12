
PROJECT = "memdemo"
VERSION = "1.0.0"

local sys = require "sys"

pmd.ldoset(3200, pmd.LDO_VLCD)

sys.taskInit(function()
    local netled = gpio.setup(1, 0)
    local count = 1
    while 1 do
        netled(1)
        sys.wait(1000)
        netled(0)
        sys.wait(1000)
        log.info("luatos", "hi", count, os.date())
        log.info("luatos", rtos.meminfo())
        log.info("luatos", rtos.meminfo("sys"))
        count = count + 1
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
