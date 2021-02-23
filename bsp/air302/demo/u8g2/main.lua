--- 模块功能：u8g2demo
-- @module u8g2
-- @author Dozingfiretruck
-- @release 2021.01.25

--[[ 注意：如需使用u8g2的全中文字库需将 luat_base.h中26行#define USE_U8G2_WQY12_T_GB2312 打开]]

-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "dispdemo"
VERSION = "1.0.0"

-- sys库是标配
_G.sys = require("sys")


-- 日志TAG, 非必须
local TAG = "main"
local last_temp_data = "0"

-- 初始化显示屏
log.info(TAG, "init ssd1306")

u8g2.begin({mode="i2c_sw", pin0=17, pin1=18}) -- 通过GPIO17 SLK/GPIO18 SDA模拟, 也可以用硬件i2c脚

--u8g2.begin("ssd1306")
u8g2.SetFontMode(1)
u8g2.ClearBuffer()
u8g2.SetFont("u8g2_font_ncenB08_tr")
u8g2.DrawUTF8("U8g2+LuatOS", 32, 22)
u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
u8g2.DrawUTF8("中文测试", 40, 38)
u8g2.SendBuffer()

-- 联网主流程
sys.taskInit(function()
    sys.wait(2000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("屏幕宽度", 20, 24)
    u8g2.DrawUTF8("屏幕高度", 20, 42)
    u8g2.SetFont("u8g2_font_ncenB08_tr")
    u8g2.DrawUTF8(":"..u8g2.GetDisplayWidth(), 72, 24)
    u8g2.DrawUTF8(":"..u8g2.GetDisplayHeight(), 72, 42)
    u8g2.SendBuffer()

    sys.wait(2000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("画线测试：", 30, 24)
    for i = 0, 128, 8 do
        u8g2.DrawLine(0,40,i,40)
        u8g2.DrawLine(0,60,i,60)
        u8g2.SendBuffer()
    end

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("画圆测试：", 30, 24)
    u8g2.DrawCircle(30,50,10,15)
    u8g2.DrawDisc(90,50,10,15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("椭圆测试：", 30, 24)
    u8g2.DrawEllipse(30,50,6,10,15)
    u8g2.DrawFilledEllipse(90,50,6,10,15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("方框测试：", 30, 24)
    u8g2.DrawBox(30,40,30,24)
    u8g2.DrawFrame(90,40,30,24)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("圆角方框：", 30, 24)
    u8g2.DrawRBox(30,40,30,24,8)
    u8g2.DrawRFrame(90,40,30,24,8)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("符号测试：", 30, 24)
    u8g2.DrawUTF8("显示雪人", 30, 38)
    u8g2.SetFont("u8g2_font_unifont_t_symbols")
    u8g2.DrawGlyph( 50, 60, 0x2603 )
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.SetFont("u8g2_font_wqy12_t_gb2312")
    u8g2.DrawUTF8("三角测试：", 30, 24)
    u8g2.DrawTriangle(30,60, 60,30, 90,60)
    u8g2.SendBuffer()

    sys.wait(3000)
    u8g2.close()
    while true do
        sys.wait(1000)
    end
end)

-- TODO: 用户按钮(PB7), 用于清除配网信息,重新airkiss

-- TODO: 联网更新脚本和底层(也许)

-- 主循环, 必须加
sys.run()
