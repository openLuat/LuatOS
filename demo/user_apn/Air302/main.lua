
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "user_apn"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
local TAG="user_apn"
-- 日志TAG, 非必须
local NETLED = gpio.setup(19, 0)

sys.taskInit(function()
	local pdp_type, apn, user, name = nbiot.userApn()
	log.info(TAG, "before", pdp_type, apn, user, name)
	nbiot.userApn("cmnet", "user", "password")
	pdp_type, apn, user, name = nbiot.userApn()
	log.info(TAG, "after", pdp_type, apn, user, name)
    while 1 do
        if socket.isReady() then
            NETLED(1)
            sys.wait(100)
            NETLED(0)
            sys.wait(1900)
        else
            NETLED(1)
            sys.wait(500)
            NETLED(0)
            sys.wait(500)
        end
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
