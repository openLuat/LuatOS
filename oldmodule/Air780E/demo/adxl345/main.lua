
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "adxl345_demo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- 一定要添加sys.lua !!!!
sys = require("sys")

-- 添加硬狗防止程序卡死
if wdt then
    wdt.init(9000) -- 初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗
end

local adxl34x = require "adxl34x"

i2cid = 0
i2c_speed = i2c.FAST

gpio.setup(24, function() --配置wakeup中断，外部唤醒用 示例使用gpio24 连接ADXL34X INT1引脚
    log.info("gpio ri")
end, gpio.PULLUP, gpio.FALLING)

sys.taskInit(function()
    i2c.setup(i2cid, i2c_speed)

    adxl34x.init(i2cid)--初始化,传入i2c_id

    sys.wait(50)
    adxl34x.set_thresh(i2cid, string.char(0x05), string.char(0x02), string.char(0x05))  -- 设置阀值
    sys.wait(50)
    adxl34x.set_irqf(i2cid, string.char(0x00), string.char(0xff), string.char(0x10))     -- activity映射到到INT1，并开启对应中断功能

    while 1 do
        adxl34x.get_int_source(i2cid)    -- 不加这个不会触发中断
        
        local adxl34x_data = adxl34x.get_data()
        log.info("adxl34x_data", "adxl34x_data.x"..(adxl34x_data.x),"adxl34x_data.y"..(adxl34x_data.y),"adxl34x_data.z"..(adxl34x_data.z))
        sys.wait(1000)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
