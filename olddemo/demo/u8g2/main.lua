--- 模块功能：u8g2demo
-- @module u8g2
-- @author Dozingfiretruck
-- @release 2021.01.25

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "u8g2demo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")

--[[
I2C0
I2C0_SCL               (5)
I2C0_SDA               (4)
]]

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗

local rtos_bsp = rtos.bsp()
local chip_type = hmeta.chip()

-- hw_i2c_id,sw_i2c_scl,sw_i2c_sda,spi_id,spi_res,spi_dc,spi_cs,spi_clk,spi_mosi
function u8g2_pin()
    if rtos_bsp == "EC618" then
        return 0,10,11,0,1,10,8,11,9
    elseif string.find(rtos_bsp,"EC718") or string.find(chip_type,"EC718") then
        return 0,29,30
    elseif string.find(rtos_bsp,"Air8101") then
        return 0,8,9
    elseif string.find(rtos_bsp,"Air1601") or string.find(rtos_bsp,"Air1602") then
        return 0,12,14, 1,12,14,8,9,11
    else
        log.info("main", "bsp not support")
        return
    end
end

local hw_i2c_id,sw_i2c_scl,sw_i2c_sda,spi_id,spi_res,spi_dc,spi_cs,spi_clk,spi_mosi = u8g2_pin()

-- 日志TAG, 非必须
local TAG = "main"

-- 初始化显示屏
log.info(TAG, "init ssd1306")

-- 初始化硬件i2c的ssd1306
u8g2.begin({ic = "ssd1306",direction = 0,mode="i2c_hw",i2c_id=hw_i2c_id,i2c_speed = i2c.FAST}) -- direction 可选0 90 180 270
-- 初始化软件i2c的ssd1306
-- u8g2.begin({ic = "ssd1306",direction = 0,mode="i2c_sw", i2c_scl=sw_i2c_scl, i2c_sda=sw_i2c_sda})
-- 初始化硬件spi的ssd1306
-- u8g2.begin({ic = "ssd1306",direction = 0,mode="spi_hw_4pin",spi_id=spi_id,spi_res=spi_res,spi_dc=spi_dc,spi_cs=spi_cs})

-- u8g2.begin({ic = "st7565",direction = 0,mode="spi_hw_4pin",spi_id=spi_id,spi_res=spi_res,spi_dc=spi_dc,spi_cs=spi_cs})

-- 初始化硬件spi的自定义命令SSD1306屏幕
-- u8g2.begin({ic = "custom",direction = 0,mode="spi_hw_4pin",spi_id=spi_id,spi_res=spi_res,spi_dc=spi_dc,spi_cs=spi_cs},
--             {
--                 width = 128, --分辨率宽度，128像素；用户根据屏的参数自行修改
--                 height = 64, --分辨率高度，64像素；用户根据屏的参数自行修改
--                 flush_mode = u8g2.flush_page, --可省略，custom默认使用标准分页寻址
--                 --初始化命令
--                 -- 0001 delay  延时, 例如 00010002 , 延时2ms
--                 -- 0002 cmd    发命令, 例如 0002004, dc设置为CMD模式, SPI发送 0x04
--                 -- 0003 data   发数据, 例如 0003004, dc设置为DATA模式, SPI发送 0x04
--                 initcmd =
--                 {
--                     0x000200ae,
--                     0x000200d5,
--                     0x00020080,
--                     0x000200a8,
--                     0x0002003f,
--                     0x000200d3,
--                     0x00020000,
--                     0x00020040,
--                     0x0002008d,
--                     0x00020014,
--                     0x00020020,
--                     0x00020000,
--                     0x000200a1,
--                     0x000200c8,
--                     0x000200da,
--                     0x00020012,
--                     0x00020081,
--                     0x000200cf,
--                     0x000200d9,
--                     0x000200f1,
--                     0x000200db,
--                     0x00020040,
--                     0x0002002e,
--                     0x000200a4,
--                     0x000200a6,
--                 },
--                 --休眠命令
--                 sleepcmd = 0xAE,
--                 --唤醒命令
--                 wakecmd = 0xAF,
--             }
--         ) -- direction 可选0 90 180 270

-- 初始化硬件i2c的自定义命令SSD1306屏幕
-- u8g2.begin({ic = "custom",direction = 0,mode="i2c_hw",i2c_id=hw_i2c_id,i2c_speed=i2c.FAST},
--             {
--                 width = 128,
--                 height = 64,
--                 flush_mode = u8g2.flush_page,
--                 initcmd =
--                 {
--                     0x000200ae,
--                     0x000200d5,
--                     0x00020080,
--                     0x000200a8,
--                     0x0002003f,
--                     0x000200d3,
--                     0x00020000,
--                     0x00020040,
--                     0x0002008d,
--                     0x00020014,
--                     0x00020020,
--                     0x00020000,
--                     0x000200a1,
--                     0x000200c8,
--                     0x000200da,
--                     0x00020012,
--                     0x00020081,
--                     0x000200cf,
--                     0x000200d9,
--                     0x000200f1,
--                     0x000200db,
--                     0x00020040,
--                     0x0002002e,
--                     0x000200a4,
--                     0x000200a6,
--                 },
--                 sleepcmd = 0xAE,
--                 wakecmd = 0xAF,
--             }
--         )

-- -- 初始化软件i2c的自定义命令SSD1306屏幕
-- u8g2.begin({ic = "custom",direction = 0,mode="i2c_sw",i2c_scl=sw_i2c_scl,i2c_sda=sw_i2c_sda},
--             {
--                 width = 128,
--                 height = 64,
--                 flush_mode = u8g2.flush_page,
--                 initcmd =
--                 {
--                     0x000200ae,
--                     0x000200d5,
--                     0x00020080,
--                     0x000200a8,
--                     0x0002003f,
--                     0x000200d3,
--                     0x00020000,
--                     0x00020040,
--                     0x0002008d,
--                     0x00020014,
--                     0x00020020,
--                     0x00020000,
--                     0x000200a1,
--                     0x000200c8,
--                     0x000200da,
--                     0x00020012,
--                     0x00020081,
--                     0x000200cf,
--                     0x000200d9,
--                     0x000200f1,
--                     0x000200db,
--                     0x00020040,
--                     0x0002002e,
--                     0x000200a4,
--                     0x000200a6,
--                 },
--                 sleepcmd = 0xAE,
--                 wakecmd = 0xAF,
--             }
--         )

-- 初始化软件spi的自定义命令SSD1306屏幕
-- 软件SPI需在u8g2_pin()中按开发板填写spi_clk和spi_mosi
-- u8g2.begin({ic = "custom",direction = 0,mode="spi_sw_4pin",spi_clk=spi_clk,spi_mosi=spi_mosi,spi_res=spi_res,spi_dc=spi_dc,spi_cs=spi_cs},
--             {
--                 width = 128,
--                 height = 64,
--                 flush_mode = u8g2.flush_page,
--                 initcmd =
--                 {
--                     0x000200ae,
--                     0x000200d5,
--                     0x00020080,
--                     0x000200a8,
--                     0x0002003f,
--                     0x000200d3,
--                     0x00020000,
--                     0x00020040,
--                     0x0002008d,
--                     0x00020014,
--                     0x00020020,
--                     0x00020000,
--                     0x000200a1,
--                     0x000200c8,
--                     0x000200da,
--                     0x00020012,
--                     0x00020081,
--                     0x000200cf,
--                     0x000200d9,
--                     0x000200f1,
--                     0x000200db,
--                     0x00020040,
--                     0x0002002e,
--                     0x000200a4,
--                     0x000200a6,
--                 },
--                 sleepcmd = 0xAE,
--                 wakecmd = 0xAF,
--             }
--         )

-- custom已内置双行查表刷新，不需要编译st7305型号驱动
-- 初始化硬件spi的自定义命令ST7305 200x200屏幕
-- u8g2.begin({ic = "custom",direction = 0,mode="spi_hw_4pin",spi_id=spi_id,spi_res=spi_res,spi_dc=spi_dc,spi_cs=spi_cs},
--             {
--                 width = 200,
--                 height = 200,
--                 tile_w = 26, --ST7305 200x200需要26字节行跨度
--                 tile_h = 25,
--                 flush_mode = u8g2.flush_window_2row_lut,
--                 column_start = 0x16,
--                 row_offset = 0,
--                 -- 0001 delay，低16位为延时毫秒数
--                 -- 0002 cmd，发送命令
--                 -- 0003 data，发送命令参数/数据
--                 initcmd =
--                 {
--                     0x00020001, 0x00010064,
--                     0x00020028,
--                     0x000200c7, 0x00030026, 0x000300e9,
--                     0x000200d1, 0x00030000, 0x00010014,
--                     0x00020010, 0x00010014,
--                     0x00020001, 0x00010014,
--                     0x000200d6, 0x00030017, 0x00030002,
--                     0x000200d1, 0x00030001,
--                     0x000200c0, 0x00030012, 0x0003000a,
--                     0x000200c1, 0x00030073, 0x0003003e, 0x0003003c, 0x0003003c,
--                     0x000200c2, 0x00030000, 0x00030021, 0x00030023, 0x00030023,
--                     0x000200c4, 0x00030032, 0x0003005c, 0x0003005a, 0x0003005a,
--                     0x000200c5, 0x00030032, 0x00030035, 0x00030037, 0x00030037,
--                     0x000200d8, 0x00030080, 0x000300e9,
--                     0x000200b2, 0x00030012,
--                     0x000200b3, 0x000300e5, 0x000300f6,
--                     0x00030017, 0x00030077, 0x00030077, 0x00030077,
--                     0x00030077, 0x00030077, 0x00030077, 0x00030071,
--                     0x000200b4, 0x00030005, 0x00030046,
--                     0x00030077, 0x00030077, 0x00030077,
--                     0x00030077, 0x00030076, 0x00030045,
--                     0x00020062, 0x00030032, 0x00030003, 0x0003001f,
--                     0x000200b7, 0x00030013,
--                     0x000200b0, 0x00030032,
--                     0x00020011, 0x00010078,
--                     0x000200c9, 0x00030000,
--                     0x00020036, 0x000300a4,
--                     0x0002003a, 0x00030011,
--                     0x000200b9, 0x00030020,
--                     0x000200b8, 0x00030029,
--                     0x0002002a, 0x00030016, 0x00030027,
--                     0x0002002b, 0x00030000, 0x00030063,
--                     0x00020035, 0x00030000,
--                     0x000200d0, 0x000300ff,
--                     0x00020038,
--                     0x00020029,
--                     0x00020020,
--                     0x000200bb, 0x0003004f,
--                     0x00010064,
--                 },
--                 sleepcmd = 0x28,
--                 wakecmd = 0x29,
--             }
--         )

-- 初始化硬件spi的自定义命令ST7305 168x384屏幕
-- u8g2.begin({ic = "custom",direction = 0,mode="spi_hw_4pin",spi_id=spi_id,spi_res=spi_res,spi_dc=spi_dc,spi_cs=spi_cs},
--             {
--                 width = 168,
--                 height = 384,
--                 tile_w = 21, --ST7305 200x200需要26字节行跨度
--                 tile_h = 48,
--                 flush_mode = u8g2.flush_window_2row_lut,
--                 column_start = 0x17,
--                 row_offset = 0,
--                 -- 0001 delay，低16位为延时毫秒数
--                 -- 0002 cmd，发送命令
--                 -- 0003 data，发送命令参数/数据
--                 initcmd = {
--                     0x00020001, 0x00010064,

--                     0x000200D6, 0x00030013, 0x00030002,
--                     0x000200D1, 0x00030001,
--                     0x000200C0, 0x00030012, 0x0003000A,

--                     0x000200C1, 0x0003003C, 0x0003003E, 0x0003003C, 0x0003003C,
--                     0x000200C2, 0x00030023, 0x00030021, 0x00030023, 0x00030023,
--                     0x000200C4, 0x0003005A, 0x0003005C, 0x0003005A, 0x0003005A,
--                     0x000200C5, 0x00030037, 0x00030035, 0x00030037, 0x00030037,

--                     0x000200D8, 0x000300A6, 0x000300E9,
--                     0x000200B2, 0x00030012,

--                     0x000200B3, 0x000300E5, 0x000300F6, 0x00030017, 0x00030077,
--                     0x00030077, 0x00030077, 0x00030077, 0x00030077, 0x00030077, 0x00030071,

--                     0x000200B4, 0x00030005, 0x00030046,
--                     0x00030077, 0x00030077, 0x00030077,
--                     0x00030077, 0x00030076, 0x00030045,

--                     0x00020062, 0x00030032, 0x00030003, 0x0003001F,
--                     0x000200B7, 0x00030013,
--                     0x000200B0, 0x00030060,

--                     0x00020011, 0x0001000A,

--                     0x000200C9, 0x00030000,
--                     0x00020036, 0x00030048,
--                     0x0002003A, 0x00030011,
--                     0x000200B9, 0x00030020,
--                     0x000200B8, 0x00030029,

--                     0x0002002A, 0x00030017, 0x00030024,
--                     0x0002002B, 0x00030000, 0x000300BF,
--                     0x00020035, 0x00030000,
--                     0x000200D0, 0x000300FF,

--                     0x00020038,
--                     0x00020029,
--                     0x00020020,
--                     0x000200BB, 0x0003004F,
--                     },
--                 sleepcmd = 0x28,
--                 wakecmd = 0x29,
--             }
--         )


u8g2.SetFontMode(1)
u8g2.ClearBuffer()
-- u8g2.SetFont(u8g2.font_opposansm8)
-- u8g2.SetFont(u8g2.font_opposansm18)
u8g2.SetFont(u8g2.font_opposansm24_chinese)

u8g2.DrawUTF8("U8g2+LuatOS", 32, 22)

if u8g2.font_opposansm12_chinese then
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
elseif u8g2.font_opposansm10_chinese then
    u8g2.SetFont(u8g2.font_opposansm10_chinese)
elseif u8g2.font_sarasa_m12_chinese then
    u8g2.SetFont(u8g2.font_sarasa_m12_chinese)
elseif u8g2.font_sarasa_m10_chinese then
    u8g2.SetFont(u8g2.font_sarasa_m10_chinese)
else
    print("no chinese font")
end

u8g2.DrawUTF8("中文测试", 40, 38) -- 若中文不显示或乱码,代表所刷固件不带这个字号的字体数据, 可自行云编译一份. wiki.luatos.com 有文档.
u8g2.SendBuffer()

--主流程
sys.taskInit(function()
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("屏幕宽度", 0, 24)
    u8g2.DrawUTF8("屏幕高度", 0, 42)
    u8g2.DrawUTF8(":"..u8g2.GetDisplayWidth(), 80, 24)
    u8g2.DrawUTF8(":"..u8g2.GetDisplayHeight(), 80, 42)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("画线测试：", 30, 24)
    for i = 0, 128, 8 do
        u8g2.DrawLine(0,40,i,40)
        u8g2.DrawLine(0,60,i,60)
        u8g2.SendBuffer()
        sys.wait(100)
    end

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("画圆测试：", 30, 24)
    u8g2.DrawCircle(30,50,10,15)
    u8g2.DrawDisc(90,50,10,15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("椭圆测试：", 30, 24)
    u8g2.DrawEllipse(30,50,6,10,15)
    u8g2.DrawFilledEllipse(90,50,6,10,15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("方框测试：", 30, 24)
    u8g2.DrawBox(30,40,30,24)
    u8g2.DrawFrame(90,40,30,24)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("圆角方框：", 30, 24)
    u8g2.DrawRBox(30,40,30,24,8)
    u8g2.DrawRFrame(90,40,30,24,8)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("三角测试：", 30, 24)
    u8g2.DrawTriangle(30,60, 60,30, 90,60)
    u8g2.SendBuffer()


    -- qrcode测试
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawDrcode(4, 4, "https://docs.openluat.com", 30);
    u8g2.SendBuffer()

    --sys.wait(1000)
    log.info("main", "u8g2 demo done")
end)

-- 主循环, 必须加
sys.run()
