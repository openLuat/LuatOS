
PROJECT = "hi"
VERSION = "1.0.0"

local sys = require "sys"

sys.taskInit(function()
    while 1 do
        log.info("luatos", "hi", os.date())
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
