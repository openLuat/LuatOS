
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ec618_w5500"
VERSION = "1.2"
-- PRODUCT_KEY = "s1uUnY6KA06ifIjcutm5oNbG3MZf5aUv" --换成自己的

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)

--[[
本demo是 Air780E + w5500. 以 Air780E开发板为例, 接线如下:

Air780E            W5500
GND(任意)          GND
GPIO18             IRQ/INT,中断
GPIO01             RST, 复位
GPIO08/SPI0_CS     CS/SCS,片选    
GPIO11/SPI0_SLK    SLK,时钟
GPIO09/SPI0_MOSI   MOSI,主机输出,从机输入
GPIO10/SPI0_MISO   MISO,主机输入,从机输出

最后是供电, 这样要根据W5500的板子来选:
1. 如果是5V的, 那么接780E开发板的5V
2. 如果是3.3V的, 另外找一个3.3V, 例如CH340小板子, 额外供电

注意: 额外供电时候, W5500的GND和Air780E依然需要接起来.
]]


-- 配置W5500
-- 0            -- SPI0
-- 25600000     -- 25.6M波特率, Air780E的最高波特率
-- 8            -- CS片选脚
-- 18           -- INT/IRQ中断脚
-- 1            -- RST复位脚
w5500.init(0, 25600000, 8, 18, 1)
w5500.config()	--默认是DHCP模式,其他模块请查阅w5500库的API
w5500.bind(socket.ETH0) -- 固定写法

----------------------------------------
-- 报错信息自动上报到平台,默认是iot.openluat.com
-- 支持自定义, 详细配置请查阅API手册
-- 开启后会上报开机原因, 这需要消耗流量,请留意
-- if errDump then
--     errDump.config(true, 600)
-- end
----------------------------------------


-- 如果运营商自带的DNS不好用，可以用下面的公用DNS
-- socket.setDNS(nil,1,"223.5.5.5")	
-- socket.setDNS(nil,2,"114.114.114.114")

-- NTP 按需开启
-- socket.sntp()
--socket.sntp("ntp.aliyun.com") --自定义sntp服务器地址
--socket.sntp({"ntp.aliyun.com","ntp1.aliyun.com","ntp2.aliyun.com"}) --sntp自定义服务器地址
-- sys.subscribe("NTP_UPDATE", function()
--     log.info("sntp", "time", os.date())
-- end)
-- sys.subscribe("NTP_ERROR", function()
--     log.info("socket", "sntp error")
--     socket.sntp()
-- end)

-- 780E和W5500都有IP_READY/IP_LOSE消息,通过adapter区分
sys.subscribe("IP_READY", function(ip, adapter)
    log.info("ipready", ip, adapter) 
end)
sys.subscribe("IP_LOSE", function(adapter)
    log.info("iplose", adapter)
end)

-----------------------------------------------------------------------------
-- netlab.luatos.com上打开TCP，然后修改IP和端口号，自动回复netlab下发的数据，自收自发测试
-- 以下端口号均为临时端口, 要改成自己的值
-----------------------------------------------------------------------------

server_ip = "152.70.80.204"
server_port = 55026    -- TCP测试的端口
UDP_port = 55026      -- UDP测试的端口
ssl_port = 55026      -- TCP-SSL的测试端口

-- 与日常写法最大的区别,就是创建socket/http/ftp/mqtt时需要指定网卡 socket.ETH0
require "async_socket_demo"
socketDemo()

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!