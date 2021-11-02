--- 模块功能：u8g2demo
-- @module u8g2
-- @author Dozingfiretruck
-- @release 2021.01.25

local sys = require("sys")

--[[ 注意：如需使用u8g2的全中文字库需将 luat_base.h中26行#define USE_U8G2_WQY12_T_GB2312 打开]]

-- 项目信息,预留
VERSION = "1.0.1"
PROJECT = "demou8g2"

-- 日志TAG, 非必须
local TAG = "main"

pmd.ldoset(3000, pmd.LDO_VLCD)
--pmd.ldoset(3300, pmd.LDO_VIBR)

sys.taskInit(function()
    local netled = gpio.setup(1, 0)
    local netmode = gpio.setup(4, 0)
    local count = 1
    while 1 do
        netled(1)
        netmode(0)
        sys.wait(500)
        netled(0)
        netmode(1)
        sys.wait(500)
        log.info("luatos", "hi", count, os.date())
        count = count + 1
    end
end)

function u8g2_init()
    -- 初始化显示屏
    log.info(TAG, "init ssd1306")
    -- 模拟I2C
    --u8g2.begin({mode="i2c_sw", pin0=18, pin1=19})
    u8g2.begin({ic ="ssd1306",mode="i2c_sw", pin0=14, pin1=15})
    
    -- 硬件I2C
    --i2c.setup(1, i2c.FAST)
    --u8g2.begin({mode="i2c_hw", i2c_id=1,i2c_speed = i2c.FAST})

    -- 硬件4线SPI
    --u8g2.begin({mode="spi_hw_4pin",spi_id=1,OLED_SPI_PIN_RES=20,OLED_SPI_PIN_DC=28,OLED_SPI_PIN_CS=29})

    u8g2.SetFontMode(1)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm8)
    u8g2.DrawUTF8("U8g2+LuatOS", 32, 22)
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("中文测试", 40, 38)
    u8g2.SendBuffer()
end

-- 联网主流程
function test_u8g2()
    sys.wait(2000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("屏幕宽度", 20, 24)
    u8g2.DrawUTF8("屏幕高度", 20, 42)
    u8g2.SetFont(u8g2.font_opposansm8)
    u8g2.DrawUTF8(":"..u8g2.GetDisplayWidth(), 72, 24)
    u8g2.DrawUTF8(":"..u8g2.GetDisplayHeight(), 72, 42)
    u8g2.SendBuffer()

    sys.wait(2000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("画线测试：", 30, 24)
    for i = 0, 128, 8 do
        u8g2.DrawLine(0,40,i,40)
        u8g2.DrawLine(0,60,i,60)
        u8g2.SendBuffer()
    end

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("画圆测试：", 30, 24)
    u8g2.DrawCircle(30,50,10,15)
    u8g2.DrawDisc(90,50,10,15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("椭圆测试：", 30, 24)
    u8g2.DrawEllipse(30,50,6,10,15)
    u8g2.DrawFilledEllipse(90,50,6,10,15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("方框测试：", 30, 24)
    u8g2.DrawBox(30,40,30,24)
    u8g2.DrawFrame(90,40,30,24)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("圆角方框：", 30, 24)
    u8g2.DrawRBox(30,40,30,24,8)
    u8g2.DrawRFrame(90,40,30,24,8)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("符号测试：", 30, 24)
    u8g2.DrawUTF8("显示雪人", 30, 38)
    u8g2.SetFont(u8g2.font_unifont_t_symbols)
    u8g2.DrawGlyph( 50, 60, 0x2603 )
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont(u8g2.font_opposansm12_chinese)
    u8g2.DrawUTF8("三角测试：", 30, 24)
    u8g2.DrawTriangle(30,60, 60,30, 90,60)
    u8g2.SendBuffer()

    sys.wait(3000)
    
end


sys.taskInit(function ()
    sys.wait(15000)
    u8g2_init()
    while true do
        sys.wait(1000)
        test_u8g2()
    end
end)



-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
