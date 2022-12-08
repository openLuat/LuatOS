-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "smsdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 暂时只能发短信, 且只能发英文短信
log.info("main", "sms demo")

sys.taskInit(function()
    sys.wait(10000)
    sms.send("13912341234", "Hi, from LuatOS - " .. os.date())
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
