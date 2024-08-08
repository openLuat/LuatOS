
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "sc7a20_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end
 
local sc7a20 = require "sc7a20"

i2cid = 0
i2c_speed = i2c.FAST

gpio.setup(24, function() --配置中断，外部唤醒用
    log.info("gpio 24")
end, gpio.PULLUP, gpio.BOTH)

gpio.setup(2, function() --配置中断，外部唤醒用
    log.info("gpio 2")
end, gpio.PULLUP, gpio.BOTH)

sys.taskInit(function()
    i2c.setup(i2cid, i2c_speed)

    sc7a20.init(i2cid)--初始化,传入i2c_id

    sys.wait(50)
    sc7a20.set_thresh(i2cid, string.char(0x05), string.char(0x05))  -- 设置活动阀值
    sys.wait(50)
    sc7a20.set_irqf(i2cid, 1, string.char(0x1F), string.char(0x03), string.char(0xFF))  -- AOI1中断映射到INT1上
    sys.wait(50)
    sc7a20.set_irqf(i2cid, 2, string.char(0x1F), string.char(0x03), string.char(0xFF))  -- AOI2中断映射到INT2上

    while 1 do
        local sc7a20_data = sc7a20.get_data()
        log.info("sc7a20_data", "sc7a20_data.x"..(sc7a20_data.x),"sc7a20_data.y"..(sc7a20_data.y),"sc7a20_data.z"..(sc7a20_data.z))
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
