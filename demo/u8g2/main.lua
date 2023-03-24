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

-- hw_i2c_id,sw_i2c_scl,sw_i2c_sda,spi_id,spi_res,spi_dc,spi_cs
function u8g2_pin()     
    if rtos_bsp == "AIR101" then
        return 0,pin.PA01,pin.PA04,0,pin.PB03,pin.PB01,pin.PB04
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PA01,pin.PA04,0,pin.PB03,pin.PB01,pin.PB04
    elseif rtos_bsp == "AIR105" then
        return 0,pin.PE06,pin.PE07,5,pin.PC12,pin.PE08,pin.PC14
    elseif rtos_bsp == "ESP32C3" then
        return 0,5,4,2,10,9,7,11
    elseif rtos_bsp == "ESP32S3" then
        return 0,12,11,2,16,15,14,13
    elseif rtos_bsp == "EC618" then
        return 0,10,11,0,1,10,8,18
    else
        log.info("main", "bsp not support")
        return
    end
end

local hw_i2c_id,sw_i2c_scl,sw_i2c_sda,spi_id,spi_res,spi_dc,spi_cs = u8g2_pin() 

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

u8g2.SetFontMode(1)
u8g2.ClearBuffer()
u8g2.SetFont(u8g2.font_opposansm8)
u8g2.DrawUTF8("U8g2+LuatOS", 32, 22)

if u8g2.font_opposansm12_chinese then
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
elseif u8g2.font_opposansm10_chinese then
    u8g2.SetFont(u8g2.font_opposansm10_chinese)
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
    u8g2.DrawDrcode(4, 4, "https://wiki.luatos.com/chips/air101/mcu.html", 10);

    u8g2.SendBuffer()

    --sys.wait(1000)
    log.info("main", "u8g2 demo done")
end)

-- 主循环, 必须加
sys.run()
