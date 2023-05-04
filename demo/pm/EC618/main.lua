
-- LuaTools需要PROJECT和VERSION这两个信息
--[[
-- 演示一下pm相关API的功能
PROJECT = "pmdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
log.style(1)
-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!


-- 启动时对rtc进行判断和初始化
local reason, slp_state = pm.lastReson()
log.info("wakeup state", pm.lastReson())
if reason > 0 then
    pm.request(pm.LIGHT)
    log.info("已经从深度休眠唤醒，测试结束")
    mobile.flymode(0, false)
    sys.taskInit(function() 
        sys.wait(10000)
    end)
else
    log.info("普通复位，开始测试")
    --测试最低功耗，需要下面3个GPIO操作
    gpio.setup(23,nil)
    gpio.close(33)
    gpio.close(35) --这里pwrkey接地才需要，不接地通过按键控制的不需要
    sys.taskInit(function()
        pm.power(pm.GPS, true) --打开780EG内部GPS电源，注意如果真的用GPS，需要初始化UART2
        pm.power(pm.GPS_ANT, true) --打开780EG内部GPS天线电源，注意如果真的用GPS，需要初始化UART2
        log.info("等联网完成")
        sys.wait(20000)
        pm.power(pm.GPS, false) --打开780EG内部GPS电源，注意如果真的用GPS，需要初始化UART2
        pm.power(pm.GPS_ANT, false) --打开780EG内部GPS天线电源，注意如果真的用GPS，需要初始化UART2
        -- lvgl刷新太快，如果有lvgl.init操作的，需要先停一下
        if lvgl then
            lvgl.sleep(true)
        end
        pm.power(pm.USB, false)-- 如果是插着USB测试，需要关闭USB
        pm.force(pm.LIGHT)
        -- 如果要测试保持网络连接状态下的功耗，需要iotpower来测试 https://wiki.luatos.com/iotpower/power/index.html 购买链接 https://item.taobao.com/item.htm?id=679899121798
        -- 如果只是看普通休眠状态下的底电流，需要进入飞行模式
        -- log.info("普通休眠测试，进入飞行模式来保持稳定的电流")
        -- mobile.flymode(0, true)
        log.info("普通休眠测试，普通定时器就能唤醒，10秒后唤醒一下")
        sys.wait(10000)
        pm.force(pm.IDLE)
        pm.power(pm.USB, true)
        sys.wait(1000)
        log.info("普通休眠测试成功，接下来深度休眠，进入飞行模式或者PSM模式来保持稳定的电流，不开飞行模式会周期性唤醒，大幅度增加功耗")
        mobile.flymode(0, true)
        sys.wait(10000)
        log.info("深度休眠测试用DTIMER来唤醒")
        -- EC618上，0和1只能最多2.5小时，2~6可以750小时
        pm.dtimerStart(0, 10000)
        pm.force(pm.DEEP)   --也可以pm.HIB模式
        pm.power(pm.USB, false) -- 如果是插着USB测试，需要关闭USB
        log.info("开始深度休眠测试")
        sys.wait(3000)
        log.info("深度休眠测试失败")
    end)
end
]]
-- 演示一下周期性工作-休眠的demo
PROJECT = "sleepdemo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
log.style(1)
-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!
-- 注意:本demo使用luatools下载!!!


-- 启动时对rtc进行判断和初始化
local reason, slp_state = pm.lastReson()
log.info("wakeup state", pm.lastReson())
if reason > 0 then
    pm.request(pm.LIGHT)
	mobile.flymode(0, false)
    log.info("已经从深度休眠唤醒")
end
--测试最低功耗，需要下面3个GPIO操作
gpio.setup(23,nil)
-- gpio.close(33) --如果功耗偏高，开始尝试关闭WAKEUPPAD1
gpio.close(35) --这里pwrkey接地才需要，不接地通过按键控制的不需要

sys.taskInit(function()
	log.info("工作14秒后进入深度休眠")
	sys.wait(14000)
	mobile.flymode(0, true)
	log.info("深度休眠测试用DTIMER来唤醒")
	sys.wait(100)
	pm.power(pm.USB, false) -- 如果是插着USB测试，需要关闭USB
	pm.force(pm.HIB)
	pm.dtimerStart(3, 40000)
	sys.wait(5000)
	pm.power(pm.USB, true) -- 如果是插着USB测试，需要关闭USB
	log.info("深度休眠测试失败")
	mobile.flymode(0, false)
	pm.request(pm.LIGHT)

	while true do
		sys.wait(5000)
		log.info("深度休眠测试失败")
	end
end)




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
