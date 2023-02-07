
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
    errDump.config(true, 600)
end
----------------------------------------


-- 如果运营商自带的DNS不好用，可以用下面的公用DNS
-- socket.setDNS(nil,1,"223.5.5.5")	
-- socket.setDNS(nil,2,"114.114.114.114")

socket.sntp()
--socket.sntp("ntp.aliyun.com") --自定义sntp服务器地址
--socket.sntp({"ntp.aliyun.com","ntp1.aliyun.com","ntp2.aliyun.com"}) --sntp自定义服务器地址
sys.subscribe("NTP_UPDATE", function()
    log.info("sntp", "time", os.date())
end)
sys.subscribe("NTP_ERROR", function()
    log.info("socket", "sntp error")
    socket.sntp()
end)

-- require "async_socket_demo"
-- require "socket_demo"
require "server_demo"
SerDemo(15000)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!