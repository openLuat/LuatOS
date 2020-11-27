
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "gpiodemo"
VERSION = "1.0.0"

-- 引入必要的库文件(lua编写), 内部库不需要require
local sys = require "sys"

log.info("main", "gpio demo")
print(_VERSION)

sys.timerLoopStart(function()
    print("rdy")
end, 3000)

--sys.subscribe("IRQ_27", function(id, msg)
--    log.info("IRQ_27!!!!", id, msg)
--end)
local PB7 = 27
gpio.setup(PB7, function(msg) log.info("IQR", "PB7/27", msg) end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
