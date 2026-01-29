-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "Control_LED"
VERSION = "1.0.0"
-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")
--=============================================================
log.info("按键控制LED灯")
gpio.setup(27, 1)
gpio.setup(2, 1)--摄像头的供电LDO
gpio.setup(28, 1)--LCD的供电LDO
gpio.setup(34, nil,gpio.PULLUP)
--gpio.setup(34, nil,gpio.PULLDOWN)
--=============================================================
function LED()
    while 1 do
        local resalt=gpio.get(34)
        log.info("GPIO34的电平=",resalt)
        if resalt==1 then
            gpio.set(27,1)
            sys.wait(500)
        else
            gpio.set(27,0)
            sys.wait(500)
        end
    end   
end
--=============================================================
sys.taskInit(LED)
--=============================================================
-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!