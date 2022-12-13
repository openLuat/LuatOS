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
log.info("main", "sms demo")

-- 接收短信, 支持两种方式, 选一种就可以了
-- 1. 设置回调函数
sms.setNewSmsCb(function(num, txt, datetime)
    -- num 手机号码
    -- txt 文本内容
    -- datetime 发送时间,当前为nil,暂不支持
    log.info("sms", num, txt, txt:toHex())
end)
-- 2. 订阅系统消息
sys.subscribe("SMS_INC", function(num, txt, datetime)
    -- num 手机号码
    -- txt 文本内容
    -- datetime 发送时间,当前为nil,暂不支持
    log.info("sms", num, txt, txt:toHex())
end)

sys.taskInit(function()
    sys.wait(10000)
    -- 暂时只能发英文短信
    sms.send("10086", "Hi, from LuatOS - " .. os.date())
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
