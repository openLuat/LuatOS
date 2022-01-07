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

--[[
-- LCD接法示例, 以Air105开发板的HSPI为例
LCD管脚       Air105管脚
GND          GND
VCC          3.3V
SCL          (PC15/SPI0_SCK)
SDA          (PC13/SPI0_MOSI)
RES          (PC05)
DC           (PC12)
CS           (PC14)
BL           (PC04)


提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

-- v0006及以后版本可用pin方式, 请升级到最新固件 https://gitee.com/openLuat/LuatOS/releases
spi_lcd = spi.deviceSetup(5,pin.PC14,0,0,8,96*1000*1000,spi.MSB,1,1)

-- log.info("lcd.init",
-- lcd.init("gc9a01",{port = "device",pin_dc = pin.PC12,pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PC12, pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 0,w = 240,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PC12, pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 3,w = 240,h = 240,xoffset = 80,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PC12, pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 3,w = 320,h = 240,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7789",{port = "device",pin_dc = pin.PC12, pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735",{port = "device",pin_dc = pin.PC12, pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 0,w = 128,h = 160,xoffset = 2,yoffset = 1},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735v",{port = "device",pin_dc = pin.PC12,pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 1,w = 160,h = 80,xoffset = 0,yoffset = 24},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("st7735s",{port = "device",pin_dc = pin.PC12,pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 2,w = 160,h = 80,xoffset = 1,yoffset = 26},spi_lcd))
log.info("lcd.init",
lcd.init("gc9306",{port = "device",pin_dc = pin.PC12,pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))
-- log.info("lcd.init",
-- lcd.init("ili9341",{port = "device",pin_dc = pin.PC12, pin_rst = pin.PC05,pin_pwr = pin.PC04,direction = 0,w = 240,h = 320,xoffset = 0,yoffset = 0},spi_lcd))

sys.taskInit(function()
    -- sys.wait(1000)
    -- API 文档 https://wiki.luatos.com/api/lcd.html
    log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
    log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
    log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))
    while 1 do
        sys.wait(500)
    end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
