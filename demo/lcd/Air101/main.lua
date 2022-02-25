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
-- LCD接法示例, 以Air101开发板的SPI0为例
LCD管脚       Air101管脚
GND          GND
VCC          3.3V
SCL          (PB02/SPI0_SCK)
SDA          (PB05/SPI0_MOSI)
RES          (PB03/GPIO19)
DC           (PB01/GPIO17)
CS           (PB04/GPIO20)
BL           (PB00/GPIO16)


提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
3. 因为Air101/Air103只有一个SPI控制器,若使用多个SPI设备, 那么RES/CS请选用非SPI功能脚
4. BL可以不接的, 若使用Air10x屏幕扩展板,对准排针插上即可
]]

--添加硬狗防止程序卡死
if wdt then
    wdt.init(15000)--初始化watchdog设置为15s
    sys.timerLoopStart(wdt.feed, 10000)--10s喂一次狗
end

-- v0006及以后版本可用pin方式, 请升级到最新固件 https://gitee.com/openLuat/LuatOS/releases
spi_lcd = spi.deviceSetup(0,pin.PB04,0,0,8,20*1000*1000,spi.MSB,1,1)

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

--下面为custom方式示例,自己传入lcd指令来实现驱动,示例以st7735s做展示
-- log.info("lcd.init",
-- lcd.init("custom",{
--     port = "device",
--     pin_dc = pin.PB01, 
--     pin_pwr = pin.PB00,
--     pin_rst = pin.PB03,
--     direction = 0,
--     w = 128,
--     h = 160,
--     xoffset = 2,
--     yoffset = 1,
--     sleepcmd = 0x10,
--     wakecmd = 0x11,
--     initcmd = {--0001 delay  0002 cmd  0003 data
--         0x00020011,0x00010078,0x00020021, -- 反显
--         0x000200B1,0x00030002,0x00030035,
--         0x00030036,0x000200B2,0x00030002,
--         0x00030035,0x00030036,0x000200B3,
--         0x00030002,0x00030035,0x00030036,
--         0x00030002,0x00030035,0x00030036,
--         0x000200B4,0x00030007,0x000200C0,
--         0x000300A2,0x00030002,0x00030084,
--         0x000200C1,0x000300C5,0x000200C2,
--         0x0003000A,0x00030000,0x000200C3,
--         0x0003008A,0x0003002A,0x000200C4,
--         0x0003008A,0x000300EE,0x000200C5,
--         0x0003000E,0x00020036,0x000300C0,
--         0x000200E0,0x00030012,0x0003001C,
--         0x00030010,0x00030018,0x00030033,
--         0x0003002C,0x00030025,0x00030028,
--         0x00030028,0x00030027,0x0003002F,
--         0x0003003C,0x00030000,0x00030003,
--         0x00030003,0x00030010,0x000200E1,
--         0x00030012,0x0003001C,0x00030010,
--         0x00030018,0x0003002D,0x00030028,
--         0x00030023,0x00030028,0x00030028,
--         0x00030026,0x0003002F,0x0003003B,
--         0x00030000,0x00030003,0x00030003,
--         0x00030010,0x0002003A,0x00030005,
--         0x00020029,
--     },
--     },
--     spi_lcd))

sys.taskInit(function()
    sys.wait(1000)
    -- API 文档 https://wiki.luatos.com/api/lcd.html
    log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
    log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
    log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))
    -- while 1 do
    --     sys.wait(500)
    -- end
end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
