
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "am2320demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 引入必要的库文件(lua编写), 内部库不需要require
sys = require("sys")

-- Air780E的AT固件默认会为开机键防抖, 导致部分用户刷机很麻烦
if rtos.bsp() == "EC618" and pm and pm.PWK_MODE then
    pm.power(pm.PWK_MODE, false)
end


if wdt then
    --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

local am2320 = require "am2320"

sys.taskInit(function ()
    i2c.setup(0, i2c.FAST)
    while 1 do
        sys.wait(3000)
        local t, h = am2320.read()
        -- 若读取成功会返回2个值,否则两个值都是nil
        -- 单位分别是摄氏度和1%相对湿度
        log.info("am2320", "温度", t, "湿度", h)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!