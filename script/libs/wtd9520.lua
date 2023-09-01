--[[
@module  wtd9520
@summary 添加软件看门狗功能，防止死机
@data    2023.5.23
@author  翟科研
@usage
--local wtd9520 = require ("wtd9520")
-- 用法实例
-- sys.taskInit(function ()
--     wtd9520.init(28)
--     wtd9520.feed_dog(28,10)--28为看门狗引脚，10为设置喂狗时间
--     --wtd9520.set_time(1)--开启定时模式再打开此代码，否则无效
-- end)
]]
local sys = require "sys"
_G.sysplus = require("sysplus")
wtd9520={}
--[[
初始化引脚
@api wtd9520.init(watchdogPin)
@int 看门狗控制引脚
@return nil
@usage
wtd9520.init(28)
]]
function wtd9520.init(watchdogPin)
    gpio.setup(watchdogPin,0,gpio.PULLDOWN)
    gpio.set(watchdogPin,0)
end
function wtd9520.callback(watchdogPin)
    gpio.set(watchdogPin,0)
end
--[[
调用此函数进行喂狗
@api wtd9520.feed_dog(watchdogPin)
@int watchdogPin设置看门狗控制引脚
@return nil
@usage
wtd9520.feed_dog(28)
]]
function wtd9520.feed_dog(watchdogPin)
    local watchdogFeedDuration = 400
    gpio.set(watchdogPin,1)
    sys.timerStart(wtd9520.callback,watchdogFeedDuration,watchdogPin)
end
--[[
调用此函数关闭喂狗，谨慎使用!
@api wtd9520.close_watch_dog(watchdogPin)
@int watchdogPin设置看门狗控制引脚
@return nil
@usage
wtd9520.close_watch_dog(28)
]]
function wtd9520.close_watch_dog(watchdogPin)
    local watchdogStopDuration = 700
    gpio.set(watchdogPin,1)
    sys.timerStart(wtd9520.callback,watchdogStopDuration,watchdogPin)
end

return wtd9520
