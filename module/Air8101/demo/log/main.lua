-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "LOG"
VERSION = "2.0.0"

--[[
本demo演示 log日志的基本操作
]]

sys = require("sys")


sys.taskInit(function ()
    sys.wait(1000) -- 延时一会儿，免得看不到日志
    local tmp

    --实验1：输出四个等级的日志
	--日志等级从低到高为 debug(1) < info(2) < warn(3) < error(4)
    log.debug(PROJECT, "debug message")
    log.info(PROJECT, "info message")
    log.warn(PROJECT, "warn message")
    log.error(PROJECT, "error message")

    --实验2：输出INFO级及更高级别日志
    log.setLevel("INFO")
    print("CurrentLogLev:",log.getLevel())
    
    log.debug(PROJECT, "debug message")  -- 这条debug级别的日志不会输出
    log.info(PROJECT, "info message")	 -- 这条info级别的日志会输出
    log.warn(PROJECT, "warn message")	 -- 这条warn级别的日志会输出
    log.error(PROJECT, "error message")	 -- 这条error级别的日志会输出

    --实验3：通过日志输出变量内容
    local myInteger = 42
	log.info("Integer", myInteger)       -- 输出myInteger变量值
end)
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!