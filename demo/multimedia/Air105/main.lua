
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "test_audio"
VERSION = "2.0.0"

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

log.style(1)
require "music_demo"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
