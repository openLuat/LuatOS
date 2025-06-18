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

--[[接线方式  780EPM开发板----------------------------------SSD1306
LCD_VCC(LCD那组引脚以sim卡卡槽旁的LCD母排为1的第二个排母孔) ---(VCC)
I2C1_SCL(CAMERA_SCL)----------------------------------------(SCL)
I2C1_SDA(CAMERA_SDA)----------------------------------------(SDA)
GND---------------------------------------------------------(GND)
]]

-- 添加硬狗防止程序卡死
wdt.init(9000) -- 初始化watchdog设置为9s
sys.timerLoopStart(wdt.feed, 3000) -- 3s喂一次狗

-- gpio.setup(14, nil) -- 关闭GPIO14,防止camera复用关系出问题
-- gpio.setup(15, nil) -- 关闭GPIO15,防止camera复用关系出问题

-- mcu.altfun(mcu.I2C, 4, 67, 3, nil)
-- mcu.altfun(mcu.I2C, 4, 66, 3, nil)

local rtos_bsp = rtos.bsp()

-- hw_i2c_id,sw_i2c_scl,sw_i2c_sda,spi_id,spi_res,spi_dc,spi_cs
function u8g2_pin()
    if string.find(rtos_bsp, "780EPM") or string.find(rtos_bsp, "718PM") then
        return 1, 14, 15, 0, 14, 10, 8
    else
        log.info("main", "你用的不是780EPM 请更换demo测试")
        return
    end
end

local hw_i2c_id, sw_i2c_scl, sw_i2c_sda, spi_id, spi_res, spi_dc, spi_cs = u8g2_pin()

-- 日志TAG, 非必须
local TAG = "main"
local chinese =true
-- 主流程
sys.taskInit(function()

    gpio.setup(2, 1) -- GPIO2打开给camera电源供电
    gpio.setup(28, 1) -- 1.2版本 GPIO28打开给lcd电源供电
    gpio.setup(29, 1) -- 1.3硬件版本 GPIO29打开给lcd电源供电
    sys.wait(2000)

    -- 初始化显示屏
    log.info(TAG, "init ssd1306")

    -- 初始化硬件i2c的ssd1306
    log.info("setup SSD1306", u8g2.begin({
        ic = "ssd1306",
        direction = 0,
        mode = "i2c_hw",
        i2c_id = hw_i2c_id
    })) -- direction 可选0 90 180 270

    log.info("设置字体模式", u8g2.SetFontMode(1))
    log.info("清屏", u8g2.ClearBuffer())
    log.info("设置字体为 oppo字体", u8g2.SetFont(u8g2.font_opposansm8))
    log.info("在显示屏上展示U8G2+LUATOS", u8g2.DrawUTF8("U8G2+LUATOS", 32, 22))

    if u8g2.font_opposansm12_chinese then
        u8g2.SetFont(u8g2.font_opposansm12_chinese)
    elseif u8g2.font_opposansm10_chinese then
        u8g2.SetFont(u8g2.font_opposansm10_chinese)
    elseif u8g2.font_sarasa_m12_chinese then
        u8g2.SetFont(u8g2.font_sarasa_m12_chinese)
    elseif u8g2.font_sarasa_m10_chinese then
        u8g2.SetFont(u8g2.font_sarasa_m10_chinese)
    else
        print("没有中文字库")
        chinese = false
    end

    if chinese then
    log.info("在显示屏显示中文", u8g2.DrawUTF8("中文测试", 40, 38)) -- 若中文不显示或乱码,代表所刷固件不带这个字号的字体数据, 可自行云编译一份. wiki.luatos.com 有文档.
        
    end
    log.info("将存储器帧缓冲区的内容发送到显示器", u8g2.SendBuffer())
    sys.wait(2000)
    u8g2.ClearBuffer()
    if chinese then
        u8g2.DrawUTF8("屏幕宽度:" .. u8g2.GetDisplayWidth(), 40, 24)
        u8g2.DrawUTF8("屏幕高度:" .. u8g2.GetDisplayHeight(), 40, 42)
    else
        u8g2.DrawUTF8("width:" .. u8g2.GetDisplayWidth(), 40, 24)
        u8g2.DrawUTF8("height:" .. u8g2.GetDisplayHeight(), 40, 42)
    end
    sys.wait(5000)
    u8g2.SendBuffer()

    u8g2.ClearBuffer()
    u8g2.DrawUTF8("画线测试：", 30, 24)
    for i = 0, 128, 8 do
        u8g2.DrawLine(0, 40, i, 40)
        u8g2.DrawLine(0, 60, i, 60)
        u8g2.SendBuffer()
        sys.wait(100)
    end

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("画圆测试：", 30, 24)
    u8g2.DrawCircle(30, 50, 10, 15)
    u8g2.DrawDisc(90, 50, 10, 15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("椭圆测试：", 30, 24)
    u8g2.DrawEllipse(30, 50, 6, 10, 15)
    u8g2.DrawFilledEllipse(90, 50, 6, 10, 15)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("方框测试：", 30, 24)
    u8g2.DrawBox(30, 40, 30, 24)
    u8g2.DrawFrame(90, 40, 30, 24)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("圆角方框：", 30, 24)
    u8g2.DrawRBox(30, 40, 30, 24, 8)
    u8g2.DrawRFrame(90, 40, 30, 24, 8)
    u8g2.SendBuffer()

    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawUTF8("三角测试：", 30, 24)
    u8g2.DrawTriangle(30, 60, 60, 30, 90, 60)
    u8g2.SendBuffer()

    -- qrcode测试
    sys.wait(1000)
    u8g2.ClearBuffer()
    u8g2.DrawDrcode(4, 4, "https://wiki.luatos.com", 30);

    u8g2.SendBuffer()

    -- sys.wait(1000)
    log.info("main", "u8g2 demo done")
end)

-- 主循环, 必须加
sys.run()
