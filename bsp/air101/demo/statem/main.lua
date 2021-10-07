
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "statemdemo"
VERSION = "1.0.0"

local sys = require "sys"

--添加硬狗防止程序卡死
wdt.init(15000)--初始化watchdog设置为15s
sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗

sys.taskInit(function()
    gpio.setup(7, 0, gpio.PULLUP) 
    local sm = statem.create()
    sm:gpio_set(7, 0) -- gpio设置为低电平
    sm:usleep(10)     -- 休眠10us
    sm:gpio_set(7, 1) -- gpio设置为高电平
    sm:gpio_set(7, 0) -- gpio设置为高电平
    sm:gpio_set(7, 1) -- gpio设置为高电平
    sm:gpio_set(7, 0) -- gpio设置为高电平
    sm:gpio_set(7, 1) -- gpio设置为高电平
    sm:gpio_set(7, 0) -- gpio设置为高电平
    sm:gpio_set(7, 1) -- gpio设置为高电平
    sm:usleep(40)     -- 休眠40us
    sm:finish()
    -- 执行之,后续会支持后台执行
    sm:exec()
    while 1 do
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
