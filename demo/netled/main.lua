
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "netLeddemo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
local netLed = require("netLed")


--LED引脚判断赋值结束

local LEDA= gpio.setup(27, 0, gpio.PULLUP)


sys.taskInit(function()
    --流水灯程序
    sys.wait(5000) --延时5秒等待网络注册
    log.info("mobile.status()", mobile.status())
    while true do
        if mobile.status() == 1 then
            sys.wait(600)
            netLed.setupBreateLed(LEDA)
        end
    end
end)

-- 用户代码已结束 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
