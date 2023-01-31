
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fota_test"
VERSION = "1.1"
PRODUCT_KEY = "s1uUnY6KA06ifIjcutm5oNbG3MZf5aUv" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)
require "iot_fota"
-- require "soc_fota"
otaDemo()

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!