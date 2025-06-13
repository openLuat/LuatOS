-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Air8000_da221"
VERSION = "1.0.0"
log.info("main", PROJECT, VERSION)
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require "sys"
sysplus = require("sysplus")

gpio.setup(24, 1, gpio.PULLUP)  -- gsensor 开关
gpio.setup(164, 1, gpio.PULLUP) -- air8000 和解码芯片公用
gpio.setup(147, 1, gpio.PULLUP) -- camera的供电使能脚

local da221 = require "da221"

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
