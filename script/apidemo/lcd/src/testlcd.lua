local testlcd = {}

local sys = require "sys"

--spi编号,配置,lcd配置请按实际情况修改！
--使用前请先先看详细阅读wiki文档 https://wiki.luatos.com/api/lcd.html

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

--此示例为st7789
-- log.info("lcd.init",
-- lcd.init("custom",{
--     port = "device",
--     pin_dc = pin.PB01, 
--     pin_pwr = pin.PB00,
--     pin_rst = pin.PB03,
--     direction = 0,
--     w = 240,
--     h = 320,
--     xoffset = 0,
--     yoffset = 0,
--     sleepcmd = 0x10,
--     wakecmd = 0x11,
--     initcmd = {--0001 delay  0002 cmd  0003 data
--         0x00020036, 0x00030000, 0x0002003A, 0x00030005, 0x000200B2,
--         0x0003000C, 0x0003000C, 0x00030000, 0x00030033, 0x00030033,
--         0x000200B7, 0x00030035, 0x000200BB, 0x00030032,
--         0x000200C2, 0x00030001, 0x000200C3, 0x00030015,
--         0x000200C4, 0x00030020, 0x000200C6, 0x0003000F, 0x000200D0,
--         0x000300A4, 0x000300A1, 0x000200E0, 0x000300D0, 0x00030008,
--         0x0003000E, 0x00030009, 0x00030009, 0x00030005, 0x00030031,
--         0x00030033, 0x00030048, 0x00030017, 0x00030014, 0x00030015,
--         0x00030031, 0x00030034, 0x000200E1, 0x000300D0, 0x00030008,
--         0x0003000E, 0x00030009, 0x00030009, 0x00030015, 0x00030031,
--         0x00030033, 0x00030048, 0x00030017, 0x00030014, 0x00030015,
--         0x00030031, 0x00030034,
--         0x00020021, -- 如果发现屏幕反色，注释掉此行
--     },
--     },
--     spi_lcd))

sys.taskInit(function()
    sys.wait(1000)
    -- API 文档 https://wiki.luatos.com/api/lcd.html
    log.info("lcd.drawLine", lcd.drawLine(20,20,150,20,0x001F))
    log.info("lcd.drawRectangle", lcd.drawRectangle(20,40,120,70,0xF800))
    log.info("lcd.drawCircle", lcd.drawCircle(50,50,20,0x0CE0))
    while 1 do
        sys.wait(500)
    end
end)

return testlcd