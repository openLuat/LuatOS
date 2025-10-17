
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "camera_raw_mode"
VERSION = "1.1"
PRODUCT_KEY = "s1uUnY6KA06ifIjcutm5oNbG3MZf5aUv" --换成自己的
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)
w5500.init(spi.SPI_2, 24000000, pin.PB03, pin.PC00, pin.PE10)
w5500.config()
w5500.bind(socket.ETH0)
require "camera_raw"
--采集到摄像头原始数据，发送给局域网内的UDP服务器，由于W5500速度不够快，效果很差
camDemo("10.0.0.3", 12000)
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!