
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "irdemo"
VERSION = "1.0.0"

-- sys库是标配
sys = require("sys")


sys.taskInit(function()
    while true do
        ir.sendNEC(0, 0x11, 0x22)
        sys.wait(1000)
    end

end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
