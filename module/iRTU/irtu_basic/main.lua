-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "iRTU"
VERSION = "5.0.0"

PRODUCT_KEY = "0LkZx9Kn3tOhtW7uod48xhilVNrVsScV" --618DTU正式版本的key固定为它
-- PRODUCT_KEY = "z1OoDfAP2LDtOStiMQTVDfXO6RkrWeBG" --618DTU测试版本的key固定为它


log.info("main", PROJECT, VERSION)



require "libnet"
require "lbsLoc"

db = require("db")

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end
ver = rtos.bsp()

require "irtu_main"

mcu.hardfault(1)--死机重启

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
