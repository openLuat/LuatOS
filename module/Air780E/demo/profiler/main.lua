
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "memtest"
VERSION = "1.0.0"

--[[
lua内存分析库, 未完成
]]

-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(1000)
    collectgarbage()
    collectgarbage()
    sys.wait(1000)
    profiler.start()
    while 1 do
        log.info("sys", rtos.meminfo("sys"))
        log.info("lua", rtos.meminfo("lua"))
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
