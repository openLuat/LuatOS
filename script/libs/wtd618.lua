--- 模块功能：看门狗功能
-- @module wtd
-- @author 翟科研
-- @license MIT
-- @copyright OpenLuat.com
-- @release 2023.5.13
local wtd618={}
local sys = require "sys"
--[[特别注意, 使用mqtt库需要下列语句]]
_G.sysplus = require("sysplus")

-- 看门狗引脚
watchdogPin = 28


function wtd618_Init()
    gpio.setup(watchdogPin,0,gpio.PULLDOWN)
    gpio.set(watchdogPin,0)
end

function wtd618_callback()
    gpio.set(watchdogPin,0)
end

function wtd618_SetTime(value)--定时模式下，value每增加1，定时时间增加4小时，最长不超过24小时
    for i=value,1,-1  do
        wtd618_FeedDog()
        log.info("定时成功")
    end
end

function wtd618_FeedDog()--watchdogInterval设定喂狗间隔时常，不超过240s
    -- 喂狗时长（单位：毫秒）
        local watchdogFeedDuration = 210
            gpio.set(watchdogPin,1)
            sys.timerStart(wtd618_callback,watchdogFeedDuration)--喂狗动作
            --sys.wait(watchdogInterval*1000)

end

function wtd618_CloseWatchDog()
-- 关闭喂狗（单位：毫秒）
local watchdogStopDuration = 410
    gpio.set(watchdogPin,1)
    sys.timerStart(wtd618_callback,watchdogStopDuration)
end

return wtd618
