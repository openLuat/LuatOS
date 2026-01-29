-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ch390h"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

log.info("ch390h", "打开lan口LDO供电")
gpio.setup(20, 1)  --打开lan供电
log.info("ch390h", "打开wan口LDO供电")
gpio.setup(29, 1)  --打开wan口+3.3V供电

require "lan_wan"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

