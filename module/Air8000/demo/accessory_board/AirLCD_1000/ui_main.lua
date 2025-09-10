--[[
@module  ui_main
@summary UI子模块的主程序
@version 1.0
@date    2025.09.04
@author  江访
@usage

本demo演示的核心功能为：
1、依据显示屏配置参数初始化显示屏，点亮AirLCD_1000屏幕
2、循环显示显示图片、字符、色块等内容
3、通过接口设置背光亮度和对屏幕进行休眠和唤醒。
4、本demo使用的背光引脚,既是GPIO_1也是PWM_0引脚
5、背光引脚通过切换到PWM模式，通过调节占空比实现背光亮度调节
6、背光引脚通过切换到GPIO模式，再调用休眠/唤醒接口使屏幕进入休眠/唤醒
]]


-- 加载AirLCD_1000驱动模块
local AirLCD_1000 = require "AirLCD_1000"           -- 显示初始化执行程序

-- 配置AirLCD_1000接线引脚
local LCD_MODEL = "AirLCD_1000" -- 显示屏型号
local lcd_vcc = 141             -- 屏幕供电引脚GPIO号
local lcd_pin_rst = 36          -- 复位引脚GPIO号
local lcd_pin_pwr = 1           -- 背光引脚GPIO号
local lcd_pwm_id = 0            -- 背光引脚PWM端口号

-- UI主task，所有UI相关的代码都会通过该task进行调度
local function ui_main()

    AirLCD_1000.lcd_init(LCD_MODEL, lcd_vcc, lcd_pin_rst, lcd_pin_pwr,lcd_pwm_id)

    -- 设置字体为模组自带的opposansm12中文字体
    lcd.setFont(lcd.font_opposansm12_chinese)

    -- 清除屏幕显示
    -- lcd.clear()

    -- 主循环
    while true do
        -- 获取并打印屏幕尺寸信息,实际是初始化传入的信息
        -- log.info("屏幕尺寸", lcd.getSize())
        
        ------------------------------------------以下为图片/位图/英文显示设置------------------------------------------
        --设置前景色和背景色(RGB565格式)
        --需要放在循环内部，因为是一次性设置
        lcd.setColor(0xFFFF, 0x0000)  -- 白底黑字，背景色:白色(0xFFFF), 前景色:黑色(0x0000)，

        -- 在屏幕左上角(0,0)显示一张图片
        -- 图片路径为/luadb/logo.jpg
        lcd.showImage(0, 0, "/luadb/logo.jpg")

        -- 在位置(0,82)绘制一个16x16的位图，内容依次为“上”，“海”，“合”，“宙”
        -- 位图数据使用字符串格式表示
        lcd.drawXbm(0, 82, 16, 16, string.char(
        0x00,0x00,0x80,0x00,0x80,0x00,0x80,0x00,0x80,0x00,0x80,0x00,0x80,0x3F,0x80,0x00,
        0x80,0x00,0x80,0x00,0x80,0x00,0x80,0x00,0x80,0x00,0x80,0x00,0xFE,0x7F,0x00,0x00))

        lcd.drawXbm(18, 82, 16, 16, string.char(
        0x00,0x00,0x80,0x00,0xC4,0x7F,0x28,0x00,0x10,0x00,0xD0,0x3F,0x42,0x20,0x44,0x22,
        0x40,0x24,0xF0,0xFF,0x24,0x20,0x24,0x22,0x24,0x20,0xE2,0x7F,0x02,0x20,0x02,0x1E))

        lcd.drawXbm(36, 82, 16, 16, string.char(
        0x00,0x00,0x00,0x01,0x80,0x01,0x40,0x02,0x20,0x04,0x18,0x18,0xF4,0x6F,0x02,0x00,
        0x00,0x00,0xF8,0x1F,0x08,0x10,0x08,0x10,0x08,0x10,0x08,0x10,0xF8,0x1F,0x08,0x10))

        lcd.drawXbm(54, 82, 16, 16, string.char(
        0x00,0x00,0x80,0x00,0x00,0x01,0xFE,0x7F,0x02,0x40,0x02,0x40,0x00,0x01,0xFC,0x3F,
        0x04,0x21,0x04,0x21,0xFC,0x3F,0x04,0x21,0x04,0x21,0x04,0x21,0xFC,0x3F,0x04,0x20))

        -- 在位置(120,40)绘制一个蓝色点
        lcd.drawPoint(120, 40, 0x001F)

        -- 以(120,40)为圆心，40为半径绘制一个蓝色圆
        lcd.drawCircle(120, 40, 40, 0x001F)

        -- 从(170,40)到(280,40)绘制一条蓝色水平线
        lcd.drawLine(170, 40, 280, 40, 0x001F)

        -- 从(170,50)到(280,80)绘制一个蓝色矩形框
        lcd.drawRectangle(170, 50, 280, 80, 0x001F)


        -- 在位置(200,170)绘制一个100x100的二维码，内容为指定URL
        lcd.drawQrcode(200, 170, "https://docs.openluat.com/air8000/", 100)

        lcd.setFont(lcd.font_opposansm12)
        lcd.drawStr(20,172,"hello hezhou") --显示字符
        lcd.setFont(lcd.font_opposansm16)
        lcd.drawStr(20,189,"hello hezhou") --显示字符
        lcd.setFont(lcd.font_opposansm18)
        lcd.drawStr(20,210,"hello hezhou") --显示字符
        lcd.setFont(lcd.font_opposansm20)
        lcd.drawStr(20,233,"hello hezhou") --显示字符
        lcd.setFont(lcd.font_opposansm22)
        lcd.drawStr(20,258,"hello hezhou") --显示字符
        lcd.setFont(lcd.font_opposansm24)
        lcd.drawStr(20,285,"hello hezhou") --显示字符
        lcd.setFont(lcd.font_opposansm32)
        lcd.drawStr(20,316,"hello hezhou") --显示字符

        lcd.fill(10, 380, 150, 460, 0xF800)  -- 绘制红色矩形区域(0xF800是红色)
        lcd.fill(170, 380, 310, 460, 0x07E0)  -- 绘制绿色矩形区域(0x07E0是绿色)

        -- 主动刷新数据到屏幕
        lcd.flush()
        sys.wait(5000)

        --------------------------------------------以下为显示中文设置--------------------------------------------
        -- Air780EPM不支持中文显示
        -- Air780EHM/EGH/EHV/Air8000支持12号中文字体
        -- 中文以左下角为坐标显示与位图左上角方式不同

        -- 设置字体为opposansm12中文字体，从英文显示切换到中文前一定要设置
        lcd.setFont(lcd.font_opposansm12_chinese)
        lcd.setColor(0xFFFF, 0x0000)  -- 白底黑字，背景色:白色(0xFFFF), 前景色:黑色(0x0000)，

        -- 显示重拍按钮（左侧）
        lcd.drawStr(70, 420, "重拍", 0xFFFF)  -- 在按钮上绘制白色文字"重拍"

        -- 显示返回按钮（右侧）
        lcd.drawStr(230, 420, "返回", 0xFFFF)  -- 在按钮上绘制白色文字"返回"

        -- 在位置(160,155)绘制文本
        -- 不设置字体颜色，默认会使用lcd.setColor所设置的字体颜色
        lcd.drawStr(160, 155, "扫码进入Air8000资料站",0x0000)

        -- 主动刷新数据到屏幕
        lcd.flush()
        sys.wait(5000)
        --------------------------------------------以下为背光亮度设置--------------------------------------------
        -- 背光引脚使用PWM模式控制，pwm_id正确配置后可以实现背光控制
        -- 参数 level: 亮度级别(0-100)
        AirLCD_1000.set_backlight(5)  -- 设置背光为5%
        sys.wait(5000)
        AirLCD_1000.set_backlight(10)  -- 设置背光为10%
        sys.wait(5000)
        AirLCD_1000.set_backlight(20)  -- 设置背光为20%
        sys.wait(5000)
        AirLCD_1000.set_backlight(30)  -- 设置背光为30%
        sys.wait(5000)
        AirLCD_1000.set_backlight(40)  -- 设置背光为40%
        sys.wait(5000)
        AirLCD_1000.set_backlight(50)  -- 设置背光为50%
        sys.wait(5000)
        AirLCD_1000.set_backlight(60)  -- 设置背光为60%
        sys.wait(5000)
        AirLCD_1000.set_backlight(70)  -- 设置背光为70%
        sys.wait(5000)
        AirLCD_1000.set_backlight(80)  -- 设置背光为80%
        sys.wait(5000)
        AirLCD_1000.set_backlight(90)  -- 设置背光为90%
        sys.wait(5000)
        AirLCD_1000.set_backlight(100)  -- 设置背光为100%

        --------------------------------------------以下为屏幕休眠设置--------------------------------------------
        -- 背光引脚使用GPIO模式控制，pin_pwr正确配置可以实现背光控制

        -- 进入休眠，功耗13ma
        AirLCD_1000.set_sleep(true)    -- 进入休眠状态，此时屏幕供电需要稳定，若不稳定，唤醒后需要重新初始化屏幕
        pm.power(pm.WORK_MODE, 1)
        sys.wait(10000)
        pm.power(pm.WORK_MODE, 0)
        AirLCD_1000.set_sleep(false)   -- 唤醒屏幕，自动恢复之前的背光设置

        -- 主动刷新数据到屏幕
        lcd.flush()
        sys.wait(5000)
        ----------------------------------------以下为屏幕关闭/打开背光设置----------------------------------------
        -- --关闭LCD背光，功耗20ma
        -- AirLCD_1000.lcd_off()
        -- pm.power(pm.WORK_MODE, 1)
        -- sys.wait(15000)
        -- -- 唤醒
        -- pm.power(pm.WORK_MODE, 0)
        -- sys.wait(5000)
        -- AirLCD_1000.lcd_on()

        -- 主动刷新数据到屏幕
        -- lcd.flush()
        -- sys.wait(50)
    end
end

-- 创建UI主循环ui_main的task
sys.taskInit(ui_main)
