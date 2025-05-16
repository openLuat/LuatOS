
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "airlink"
VERSION = "1.0.4"


-- sys库是标配
_G.sys = require("sys")

sys.taskInit(function()
    sys.wait(100)
    airlink.init()
    airlink.start(1)
    sys.wait(10)
    airlink.test(1)
    sys.wait(10)

    airlink.statistics()

    airlink.test(1000)
    sys.wait(1000)
    airlink.statistics()
    -- wlan.init()
    -- wlan.connect("luatos1234", "12341234")
    -- airlink.test(1000)
    for i = 1, 20, 1 do
        airlink.test(1000)
        sys.wait(1000)
    end
    -- sys.wait(1000)
    airlink.statistics()

end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
