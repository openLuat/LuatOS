-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ch390h"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

log.info("ch390", "打开LDO供电")
gpio.setup(20, 1) -- 打开lan供电

mcu.hardfault(0) -- 死机后停机，一般用于调试状态


require "wan"
-- require "wan_http"
-- require "wan_tcp_udp_ssl"
-- require "wan_single_mqtt" --mqtt单链接
-- require"wan_ssl_mqtt" --mqtt SSL链接
-- require"wan_multilink_mqtt" --mqtt多链接
-- require "wan_ftp"
require"wan_websocket"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

