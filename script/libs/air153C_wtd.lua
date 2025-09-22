--[[
@module  air153C_wtd
@summary 添加软件看门狗功能，防止死机
@data    2023.5.23
@author  翟科研
@usage
--local air153C_wtd = require ("air153C_wtd")
-- 用法实例
-- sys.taskInit(function ()
--     air153C_wtd.init(28)
--     air153C_wtd.feed_dog(28,10)--28为看门狗引脚，10为设置喂狗时间
--     --air153C_wtd.set_time(1)--开启定时模式再打开此代码，否则无效
-- end)
]]
local sys = require "sys"
_G.sysplus = require("sysplus")
air153C_wtd={}
--[[
初始化引脚
@api air153C_wtd.init(watchdogPin)
@int 看门狗控制引脚
@return nil 无返回值
@usage
air153C_wtd.init(28)
]]
function air153C_wtd.init(watchdogPin)
    gpio.setup(watchdogPin,0,gpio.PULLDOWN)
    gpio.set(watchdogPin,0)
end
function air153C_wtd.callback(watchdogPin)
    gpio.set(watchdogPin,0)
end
--[[
调用此函数进行喂狗
@api air153C_wtd.feed_dog(watchdogPin)
@int watchdogPin设置看门狗控制引脚
@return nil 无返回值
@usage
air153C_wtd.feed_dog(28)
]]
function air153C_wtd.feed_dog(watchdogPin)
    local watchdogFeedDuration = 400
    gpio.set(watchdogPin,1)
    sys.timerStart(air153C_wtd.callback,watchdogFeedDuration,watchdogPin)
end
--[[
调用此函数关闭喂狗，谨慎使用!
@api air153C_wtd.close_watch_dog(watchdogPin)
@int watchdogPin设置看门狗控制引脚
@return nil 无返回值
@usage
air153C_wtd.close_watch_dog(28)
]]
function air153C_wtd.close_watch_dog(watchdogPin)
    local watchdogStopDuration = 700
    gpio.set(watchdogPin,1)
    sys.timerStart(air153C_wtd.callback,watchdogStopDuration,watchdogPin)
end

return air153C_wtd
