--- 字体demo

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "fontdemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--[[
SPI0
SPI0_SCK               (PB2)
SPI0_MISO              (PB3)
SPI0_MOSI              (PB5)
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(9000)--初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗
end

-- 使用全局变量, 避免spi_lcd被回收
spi_lcd = spi.deviceSetup(0,20,0,0,8,2000000,spi.MSB,1,1)

-- log.info("lcd.init",
-- lcd.init("gc9a01",{port = "device",pin_dc = 17, pin_pwr = 16,pin_rst = 19,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = 17, pin_pwr = 16,pin_rst = 19,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = 17, pin_pwr = 16,pin_rst = 19,direction = 3,w = 240,h = 240,xoffset = 80,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = 17, pin_pwr = 16,pin_rst = 19,direction = 3,w = 320,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
log.info("lcd.init",
lcd.init("st7735",{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735v",{port = "device",pin_dc = 17, pin_pwr = 16,pin_rst = 19,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735s",{port = "device",pin_dc = 17, pin_pwr = 7,pin_rst = 19,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))

--[[-- v0006及以后版本可用pin方式
spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,2000000,spi.MSB,1,1)

-- log.info("lcd.init",
-- lcd.init("gc9a01",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 3,w = 240,h = 240,xoffset = 80,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 3,w = 320,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735v",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd))
log.info("lcd.init",
lcd.init("st7735s",{port = "device",pin_dc = pin.PB01, pin_pwr = pin.PB00,pin_rst = pin.PB03,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))
]]

log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))



sys.taskInit(function()
    sys.wait(2000)
    
    local i = 0
    while 1 do
        lcd.clear(0)
        local start = mcu.ticks()
        local data = fonts.get_data(0, 0xB0A1 + i)
        local gtime = mcu.ticks() - start
        log.info("fonts", data:toHex())
        lcd.drawXbm(32, 32, 16, 16, data)
        local ltime = mcu.ticks() - start - gtime
        log.info("ticks", start, gtime, ltime)
        sys.wait(1000)
        i = i + 1
        break
    end
    
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
