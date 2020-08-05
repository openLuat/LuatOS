
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "mypwm"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

-- PWM5 --> NETLED, GPIO19
-- PWM4 --> GPIO18
-- PWM2 --> GPIO17

-- gpio.setup(19, 0)
sys.taskInit(function()
    while 1 do
        -- 仿呼吸灯效果
        log.info("pwm", ">>>>>")
        for i = 10,1,-1 do 
            pwm.open(5, 1000, i*9) -- 5 通道, 频率1000hz, 占空比0-100
            sys.wait(200 + i*10)
        end
        for i = 10,1,-1 do 
            pwm.open(5, 1000, 100 - i*9)
            sys.wait(200 + i*10)
        end
        sys.wait(5000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
