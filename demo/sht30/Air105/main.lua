
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "spi_no_blcok_test"
VERSION = "1.0"
-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")
log.style(1)
require "no_block_test"
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!