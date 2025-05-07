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

local PWM_ID = 4  -- 代码中使用pwm通道4，如需使用其他pwm通道请查看Air8000/pwm使用指南/pwm通道说明。
sys.taskInit(function()

    -- 配置IO复用，PIN24 GPIO21 FUNC5-PWM4
    gpio.setup(21, 0, nil, nil, 5) 

    log.info("pwm", "ch", PWM_ID)
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

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!