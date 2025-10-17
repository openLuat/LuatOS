-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcdsegdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require "sys"

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end


-- 初始化lcdseg
if lcdseg.setup(lcdseg.BIAS_ONETHIRD, lcdseg.DUTY_ONEFOURTH, 33, 4, 60,0xff,0xffffffff) then
    lcdseg.enable(1)

    sys.taskInit(function ()
        while 1 do
            for i=0,3 do
                for j=1,31 do
                    lcdseg.seg_set(i, j, 1)
                    sys.wait(10)
                end
            end
            for i=0,3 do
                for j=1,31 do
                    lcdseg.seg_set(i, j, 0)
                    sys.wait(10)
                end
            end
        end
    end)
end



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
