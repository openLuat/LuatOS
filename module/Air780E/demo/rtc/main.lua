--- 模块功能：rtcdemo
-- @module rtc
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "rtcdemo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

sys.taskInit(function()
    log.info("os.date()", os.date())
    local t = rtc.get()
    log.info("rtc", json.encode(t))
    sys.wait(2000)
    rtc.set({year=2021,mon=8,day=31,hour=17,min=8,sec=43})
    log.info("os.date()", os.date())
    -- rtc.timerStart(0, {year=2021,mon=9,day=1,hour=17,min=8,sec=43})
    -- rtc.timerStop(0)
    while 1 do
        log.info("os.date()", os.date())
        local t = rtc.get()
        log.info("rtc", json.encode(t))
        sys.wait(1000)
    end
end)

-- 主循环, 必须加
sys.run()
