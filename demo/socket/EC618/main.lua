
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "my_test"
VERSION = "1.2"
PRODUCT_KEY = "s1uUnY6KA06ifIjcutm5oNbG3MZf5aUv" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)

----------------------------------------
-- 报错信息自动上报到平台,默认是iot.openluat.com
-- 支持自定义, 详细配置请查阅API手册
-- 开启后会上报开机原因, 这需要消耗流量,请留意
if errDump then
    errDump.uploadConfig(true, 600)
end
----------------------------------------


require "net_test"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!