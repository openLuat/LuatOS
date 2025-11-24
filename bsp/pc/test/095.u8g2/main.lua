-- 模块功能：u8g2demo
-- @module u8g2
-- @author 刘斌
-- @release 2025.09.12

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "u8g2demo"
VERSION = "1.0.1"

log.info("main", PROJECT, VERSION)

--添加硬狗防止程序卡死
wdt.init(9000)--初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000)--3s喂一次狗


-- 主流程
sys.taskInit(function()

-- IIC屏幕引脚配置
local spi_id,spi_res,spi_dc,spi_cs,i2c_id = 0,0,1,2,0

--[[
    IIC接线图
   屏幕 —— CH347
    SCL —— SCL
    SDA —— SDA

    SPI接线图
   屏幕 —— CH347
    SCL —— SCK
    DAT —— MOSI
    DC  —— IO1
    CS  —— IO2
]]

-- 初始化IIC显示屏
-- log.info("init ssd1306")
-- u8g2.begin({ic = "ssd1306",direction = 0,mode="i2c_hw",i2c_id=i2c_id,i2c_speed = i2c.FAST}) -- direction 可选0 90 180 270

-- 初始化SPI显示屏
spi.deviceSetup(
            spi_id,  -- LCD端口号
            nil,         -- CS片选脚
            0,           -- CPHA=0
            0,           -- CPOL=0
            8,           -- 8位数据宽度
            10000000,    -- 10MHz波特率
            spi.MSB,     -- 高位先传
            1,           -- 主机模式
            1            -- 全双工模式
        )
sys.wait(300)
log.info("init st7567(SPI)")
u8g2.begin({ic = "st7567",direction = 0,mode="spi_hw_4pin",spi_id=spi_id,spi_res=spi_res,spi_dc=spi_dc,spi_cs=spi_cs})


-- 显示部分
u8g2.SetFontMode(1)
u8g2.ClearBuffer()
u8g2.SetFont(u8g2.font_opposansm12_chinese)
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

while true do

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
    u8g2.DrawDrcode(4, 4, "https://wiki.luatos.com", 30)
    u8g2.SendBuffer()

    log.info("main", "u8g2 demo done")
    end
end)

-- 主循环, 必须加
sys.run()
