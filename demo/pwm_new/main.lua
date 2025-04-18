
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pwmdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local PWM_ID = 4

sys.taskInit(function()
    log.info("pwm", "ch", PWM_ID)
    pwm.setup(PWM_ID, 1000, 90)
    pwm.start(PWM_ID)
    while 1 do
        -- 仿呼吸灯效果
        log.info("pwm", ">>>>>")
        for i = 10,1,-1 do 
            pwm.setDuty(PWM_ID, i*9) -- 频率1000hz, 占空比0-100
            -- pwm.setFreq(PWM_ID, 1000 + i*10)
            sys.wait(100 + i*10)
        end
        for i = 10,1,-1 do 
            pwm.setDuty(PWM_ID, 100 - i*9)
            -- pwm.setFreq(PWM_ID, 1000 - i*10)
            sys.wait(100 + i*10)
        end
        sys.wait(2000)
    end
    pwm.stop(PWM_ID)
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
