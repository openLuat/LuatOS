-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "LED"
VERSION = "1.0.0"
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
--=============================================================
log.info("点亮一个LED灯")
gpio.setup(27, 1)
--=============================================================
function LED()
    while 1 do
--[[         gpio.set(27,1)
        log.info("亮")
        sys.wait(1000)
        gpio.set(27,0)
        log.info("灭") 
        sys.wait(1000) ]]
        LED_toggle(1000)
    end   
end
--=============================================================
function LED_toggle(time)
        sys.wait(time)
        gpio.toggle(27)
        log.info("翻转")
end
--=============================================================
sys.taskInit(LED)
--=============================================================
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!