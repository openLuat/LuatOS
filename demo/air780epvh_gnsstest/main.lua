-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gnsstest"
VERSION = "1.0.1"
PRODUCT_KEY = "" -- 基站定位需要用到

--[[
本demo需要很多流量!!!
注意: 室内无信号!! 无法定位!!!
]]

-- sys库是标配
_G.sys = require("sys")
require("sysplus")

_G.gps_uart_id = 2

-- 演示GNSS定位, 含AGPS
require "testGnss"

-- 演示上报到MQTT服务器 对应的网页是 https://iot.openluat.com/iot/device-gnss
-- require "testMqtt"

-- 演示定位成功后切换GPIO高低电平
-- require "testGpio"

-- 本TCP演示是连接到 gps.nutz.cn 19002 端口, irtu的自定义包格式
-- 网页是 https://gps.nutz.cn/ 输入IMEI号可参考当前位置
-- 微信小程序是 irtu寻物, 点击IMEI号, 扫描模块的二维码可查看当前位置和历史轨迹
-- 服务器源码地址: https://gitee.com/wendal/irtu-gps
require "testTcp"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
