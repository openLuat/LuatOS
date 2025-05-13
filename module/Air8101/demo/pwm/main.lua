
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "pwmdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 测试一
local PWM_ID = 0  -- 代码中使用pwm通道0，如需使用其他pwm通道请查看Air8101/pwm使用指南/pwm通道说明。
sys.taskInit(function()
    while true do
        -- 开启pwm通道0，设置脉冲频率为1kHz，分频精度为1000，占空比为10/1000=1% 持续输出
        pwm.open(PWM_ID, 1000, 10, 0, 1000) -- 小灯微微发光
        log.info("pwm", "当前分频精度1000，占空比1%")
        sys.wait(1000)
        -- 开启pwm通道0，设置脉冲频率为1kHz，分频精度为256，占空比为128/256=50% 持续输出
        pwm.open(PWM_ID, 1000, 128, 0, 256) -- 小灯中等亮度
        log.info("pwm", "当前分频精度256，占空比50%")
        sys.wait(1000)
        -- 开启pwm通道0，设置脉冲频率为1kHz，分频精度为100，占空比为100/100=100% 持续输出
        pwm.open(PWM_ID, 1000, 100, 0, 100) -- 小灯很高亮度
        log.info("pwm", "当前分频精度100，占空比100%")
        sys.wait(1000)
    end
end)


-- 测试二
--[[ 
local PWM_ID = 0
sys.taskInit(function()
    log.info("pwm", "ch", PWM_ID)
    while 1 do
        -- 仿呼吸灯效果
        log.info("pwm", ">>>>>")
        -- 占空比从90%（i=10时）到9%（i=1时）
        for i = 10,1,-1 do 
            pwm.open(PWM_ID, 1000, i*9) -- 频率1000hz, 占空比0-100
            sys.wait(100 + i*10)
        end
        -- 占空比从10%增加到90%
        for i = 10,1,-1 do 
            pwm.open(PWM_ID, 1000, 100 - i*9)
            sys.wait(100 + i*10)
        end
        sys.wait(2000)
    end
end) ]]

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
