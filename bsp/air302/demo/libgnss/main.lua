
-- LuaTools需要PROJECT和VERSION这两个信息
-- 本demo处于内部测试阶段,尚未正式就绪
PROJECT = "air302_libgnss_demo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- uart2接air530, 仅tx脚.不涉及agps和星历.
uart.on(2, "recv", function(id, len)
    libgnss.parse(uart.read(2, 1024))
end)
uart.setup(2, 9600)

sys.timerLoopStart(function()
    log.info("GPS", libgnss.getIntLocation())
end, 2000) -- 两秒打印一次

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
