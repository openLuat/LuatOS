-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnsstest"
VERSION = "1.0.1"
PRODUCT_KEY = ""

--[[
本demo需要很多流量!!!
注意: 室内无信号!! 无法定位!!!

本demo对应的网页是 https://iot.openluat.com/iot/device-gnss
]]

-- sys库是标配
_G.sys = require("sys")
require("sysplus")

_G.gps_uart_id = 2

require "testGnss"
require "testMqtt"
-- require "testGpio"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
