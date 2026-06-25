-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air201_da267"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require "sys"
sysplus = require("sysplus")

-- gnss的备电 和 gsensor的供电
local vbackup = gpio.setup(24, 1)

da267 = require "manage"

da267 = require "da267"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
