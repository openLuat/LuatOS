
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

local PWM_ID = 0
if rtos.bsp() == "EC618" then
    PWM_ID = 4 -- GPIO 27, NetLed
elseif rtos.bsp() == "AIR101" or rtos.bsp() == "AIR103" then
    PWM_ID = 4 -- GPIO 4
elseif rtos.bsp():startsWith("ESP32") then
    -- 注意, ESP32系列的PWM, PWM通道均与GPIO号相同
    -- 例如需要用GPIO1输出PWM, 对应的PWM通道就是1
    -- 需要用GPIO16输出PWM, 对应的PWM通道就是16
    if rtos.bsp() == "ESP32C3" then
        PWM_ID = 12 -- GPIO 12
    elseif rtos.bsp() == "ESP32S3" then
        PWM_ID = 11 -- GPIO 11
    end
elseif rtos.bsp() == "AIR105" then
    PWM_ID = 1 -- GPIO 17
end

sys.taskInit(function()
    log.info("pwm", "ch", PWM_ID)
    while 1 do
        -- 仿呼吸灯效果
        log.info("pwm", ">>>>>")
        for i = 10,1,-1 do 
            pwm.open(PWM_ID, 1000, i*9) -- 频率1000hz, 占空比0-100
            sys.wait(100 + i*10)
        end
        for i = 10,1,-1 do 
            pwm.open(PWM_ID, 1000, 100 - i*9)
            sys.wait(100 + i*10)
        end
        sys.wait(2000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
