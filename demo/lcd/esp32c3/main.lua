--- 模块功能：lcddemo
-- @module lcd
-- @author Dozingfiretruck
-- @release 2021.01.25
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

-- 添加硬狗防止程序卡死
-- wdt.init(15000)--初始化watchdog设置为15s
-- sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗

spi_lcd = spi.deviceSetup(2, 7, 0, 0, 8, 40000000, spi.MSB, 1, 1)

--[[ 此为合宙售卖的2.4寸TFT LCD 分辨率:240X320 屏幕ic:GC9306 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.39.6c2275a1Pa8F9o&id=655959696358]]
-- lcd.init("gc9a01",{port = "device",pin_dc = 6, pin_pwr = 11,pin_rst = 10,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
-- lcd.init("st7735",{port = "device",pin_dc = 6, pin_pwr = 11,pin_rst = 10,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd)

--[[ 此为合宙售卖的1.54寸TFT LCD LCD 分辨率:240X240 屏幕ic:st7789 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.20.391445d5Ql4uJl&id=659456700222]]
-- lcd.init("st7789",{port = "device",pin_dc = 6, pin_pwr = 11,pin_rst = 10,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd)

--[[ 此为合宙售卖的0.96寸TFT LCD LCD 分辨率:160X80 屏幕ic:st7735s 购买地址:https://item.taobao.com/item.htm?id=661054472686]]
lcd.init("st7735v",{port = "device",pin_dc = 6, pin_pwr = 11,pin_rst = 10,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd)
--如果显示颜色相反，关闭反色
lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
--lcd.init("st7735s",{port = "device",pin_dc = 6, pin_pwr = 11,pin_rst = 10,direction = 2,w = 160,h = 80, xoffset = 1,yoffset = 26},spi_lcd)


sys.taskInit(function() 
    sys.wait(500)

    log.info("lcd.drawLine", lcd.drawLine(20, 20, 150, 20, 0x001F))
    log.info("lcd.drawRectangle", lcd.drawRectangle(20, 40, 120, 70, 0xF800))
    log.info("lcd.drawCircle", lcd.drawCircle(50, 50, 20, 0x0CE0))
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
