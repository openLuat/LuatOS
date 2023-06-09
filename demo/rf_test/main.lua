-- LuaTools需要PROJECT和VERSION这两个信息

PROJECT = "rf_test"

VERSION = "1.0.0"

PRODUCT_KEY = "1111"

-- 引入必要的库文件(lua编写), 内部库不需要require

_G.sys = require("sys")

mobile.rfTest(true,uart.VUART_0,0)
-- 结尾总是这一句

sys.run()

-- sys.run()之后后面不要加任何语句!!!!!