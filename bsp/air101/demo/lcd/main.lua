--- 模块功能：lcddemo
-- @module lcd
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")

--添加硬狗防止程序卡死
wdt.init(15000)--初始化watchdog设置为15s
sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗

-- spi.setup(0, 20, 0, 0, 8, 40 * 1000 * 1000, spi.MSB, 1, 1)--此方法spi总线无法挂载多设备
-- log.info("lcd.init",
-- lcd.init("st7735s",{port = 0,pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 1,w = 160,h = 80,xoffset = 1,yoffset = -54}))

local spi_lcd = spi.device_setup(0,20,0,0,8,2000000,spi.MSB,1,1)
log.info("lcd.init",
lcd.init("st7735s",{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 1,w = 160,h = 80,xoffset = 1,yoffset = -54},spi_lcd))
log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))

sys.taskInit(function()
    while 1 do
        sys.wait(500)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!