
PROJECT = "memdemo"
VERSION = "1.0.0"

sys = require("sys")

sys.taskInit(function()
    local count = 1
    while 1 do
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
