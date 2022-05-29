
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "w5500_network"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

log.style(1)

-- w5500.init(spi.SPI_2, 24000000, pin.PB03, pin.PC00, pin.PC03)
w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
-- w5500.init(spi.SPI_0, 24000000, pin.PB13, pin.PC09, pin.PC08)

w5500.config()	--默认是DHCP模式
w5500.bind(network.ETH0)
--测试server模式的话，建议用静态IP和静态DNS，当然不是强制的
--w5500.config("10.0.0.80","255.255.255.0","10.0.0.1")    
--w5500.bind(network.ETH0)
--network.setDNS(network.ETH0, 1, "114.114.114.114")

--下面演示用阻塞方式做串口透传远程服务器，简单的串口DTU，用串口3，局域网内IP，IP可以换成域名，端口换成你自己的
require "dtu_demo"
dtuDemo(3, "10.0.0.3", 12000)
-- 下面演示用回调方式实现NTP校准时间功能
require "ntp_demo"
ntpDemo()

-- require "ota_demo"
-- otaDemo()
require "server_demo"
SerDemo(14000)	--14000是本地端口
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
