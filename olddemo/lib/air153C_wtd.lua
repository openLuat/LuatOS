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
-- 版本更新说明
-- 版本号：202607011722
-- 1、更新时间：2026-07-01 17:22
-- 2、更新内容
--    新增air153C_wtd.version()接口
--    支持air153C_wtd库文件版本号管理功能，版本号的格式为：yyyymmddhhmm，表示yyyy年mm月hh日hh时mm分发布的版本
]]
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
--[[
获取库文件版本信息
@return string 年月日时分，例如："202606300102"
@usage
air153C_wtd.version()
]]
function air153C_wtd.version()
    return "202607011722"
end

log.debug("air153C_wtd", "version -> " .. air153C_wtd.version())

return air153C_wtd
