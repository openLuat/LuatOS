
-- LuaTools需要PROJECT和VERSION这两个信息
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
    sys.taskInit(function()
        log.info("等联网完成")
        sys.wait(20000)
        -- lvgl刷新太快，如果有lvgl.init操作的，需要先停一下
        lvgl.sleep(true)
        -- 如果接着USB，则需要开启强制休眠pm.force，如果没接USB，可以用pm.require
        pm.force(pm.LIGHT)
        log.info("普通休眠测试，需要先进飞行模式")
        mobile.flymode(0, true)
        log.info("普通休眠测试，普通定时器就能唤醒，10秒后唤醒一下")
        sys.wait(10000)
        pm.force(pm.IDLE)
        -- 注意如果接着USB，但是用了pm.force，实际上USB是断开的，所以下面的打印不用在luatools看到
        -- 重新插拔能看到打印，或者看UART0，或者看电流情况
        log.info("普通休眠测试成功，接下来深度休眠，需要先进飞行模式，或者PSM模式")
        
        log.info("深度休眠测试用DTIMER来唤醒")
        -- EC618上，0和1只能最多2.5小时，2~6可以750小时
        pm.dtimerStart(0, 10000)
        pm.force(pm.DEEP)   --也可以pm.HIB模式
        log.info("开始深度休眠测试")
        sys.wait(3000)
        log.info("深度休眠测试失败")
    end)
end




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
