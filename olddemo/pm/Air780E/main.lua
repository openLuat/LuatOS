-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "socket_low_power"
VERSION = "1.0"
PRODUCT_KEY = "123" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)


require "functionTest"
-- require "psm_plus"
-- require "remote_net_wakeup"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!