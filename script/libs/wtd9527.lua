--[[
@module  wtd9527
@summary 添加软件看门狗功能，防止死机
@data    2023.5.23
@author  翟科研
@usage
--local wtd9527 = require ("wtd9527")
-- 用法实例
-- sys.taskInit(function ()
--     wtd9527.init(28)
--     wtd9527.feed_dog(28,10)--28为看门狗引脚，10为设置喂狗时间
--     --wtd9527.set_time(1)--开启定时模式再打开此代码，否则无效
-- end)
]]
local sys = require "sys"
_G.sysplus = require("sysplus")
wtd9527={}
--[[
初始化引脚
@api wtd9527.init(watchdogPin)
@int 看门狗控制引脚
@return nil
@usage
wtd9527.init(28)
]]
function wtd9527.init(watchdogPin)
    gpio.setup(watchdogPin,0,gpio.PULLDOWN)
    gpio.set(watchdogPin,0)
end
function wtd9527.callback(watchdogPin)
    gpio.set(watchdogPin,0)
end
--[[
定时模式下，设置定时时间
@api wtd9527.set_time(value)
@int value每增加1，定时时间增加4小时，最长不超过24小时
@return nil
@usage
wtd9527.set_time(1)
]]
function wtd9527.set_time(value)
    for i=value,1,-1  do
        wtd9527.feed_dog()
    end
end
--[[
调用此函数进行喂狗
@api wtd9527.feed_dog(watchdogPin)
@int watchdogPin设置看门狗控制引脚
@return nil
@usage
wtd9527.feed_dog(28)
]]
function wtd9527.feed_dog(watchdogPin)
    local watchdogFeedDuration = 210
    gpio.set(watchdogPin,1)
    sys.timerStart(wtd9527.callback,watchdogFeedDuration,watchdogPin)
end
--[[
调用此函数关闭喂狗，谨慎使用!
@api wtd9527.close_watch_dog(watchdogPin)
@int watchdogPin设置看门狗控制引脚
@return nil
@usage
wtd9527.close_watch_dog(28)
]]
function wtd9527.close_watch_dog(watchdogPin)
    local watchdogStopDuration = 410
    gpio.set(watchdogPin,1)
    sys.timerStart(wtd9527.callback,watchdogStopDuration,watchdogPin)
end

return wtd9527
