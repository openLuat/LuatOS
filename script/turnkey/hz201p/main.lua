-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "HZ201P"
VERSION = "0.0.1"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
_G.sys = require "sys"

require "da267"
require "camCapture"

sys.taskInit(function()
    while 1 do
        log.info("lua", rtos.meminfo())
        log.info("lua", rtos.meminfo("sys"))
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
