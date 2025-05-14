
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

sys.taskInit(function()
    while true do
        -- 开启pwm通道4，设置脉冲频率为1kHz，分频精度为1000，占空比为10/1000=1% 持续输出
        pwm.open(4, 1000, 10, 0, 1000) -- 小灯微微发光
        sys.wait(1000)
        -- 开启pwm通道4，设置脉冲频率为1kHz，分频精度为1000，占空比为500/1000=50% 持续输出
        pwm.open(4, 1000, 500, 0, 1000) -- 小灯中等亮度
        sys.wait(1000)
        -- 开启pwm通道4，设置脉冲频率为1kHz，分频精度为1000，占空比为1000/1000=100% 持续输出
        pwm.open(4, 1000, 1000, 0, 1000) -- 小灯很高亮度
        sys.wait(1000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!