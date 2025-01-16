-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "ch390h"
VERSION = "1.0.0"

-- 使用合宙iot平台时需要这个参数
PRODUCT_KEY = "xxx" -- 到 iot.openluat.com 创建项目,获取正确的项目id

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
sysplus = require("sysplus")

-- require "lan"
require "wan"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

-- http://iot.openluat.com/api/site/firmware_upgrade?project_key=4MQAVweO8au0KQqxm4eHWnzV4ppiAZ5x&imei=864536072623240&device_key=&firmware_name=v6tracker_LuatOS-SoC_Air201&version=2002.1.5&model=Air780EPS_A13
-- http://iot.openluat.com/api/site/firmware_upgrade?project_key=epeGacglnQylV5jSKybIj1Dvqk6vm6nu&firmware_name=StudentCard_LuatOS-SoC_Air201&version=2002.1.4&imei=864536072623240