------------------------------------------以下为使用说明------------------------------------------

--[[
@module  ui_main
@summary UI子模块的主程序
@version 1.0
@date    2025.09.04
@author  江访
@usage
--------------------------------------以下为核心业务逻辑说明--------------------------------------
1、依据显示屏配置参数初始化显示屏
2、循环显示配置的内容
3、设置背光亮度
4、屏幕休眠和唤醒
]]

--------------------------------------------以下为代码--------------------------------------------
local ui_main = {}

-- 加载UI子模块
local screen_data = require "screen_data_table"     -- 显示屏配置参数
local AirLCD_1000 = require "AirLCD_1000"             -- 显示初始化执行程序


-- UI主协程，所有UI相关的代码都会通过该协程进行调度
sys.taskInit(function()
    -- 初始化显示屏
    -- 使用screen_data配置表中的参数初始化LCD，在配置表中修改即可
    local lcd_init_success  = AirLCD_1000.lcd_init()

    -- 检查LCD初始化是否成功
    if not lcd_init_success then
        log.error("ui_main", "LCD初始化失败")
        return  -- 初始化失败，退出任务
    end

    -- 设置字体为模组自带的opposansm12中文字体
    lcd.setFont(lcd.font_opposansm12_chinese)

    -- 清除屏幕显示
    lcd.clear()

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
        -- 背光引脚使用PWM引脚控制，且screen_data_table{}内pwm_id正确配置后可以实现背光控制
        -- 参数 level: 亮度级别(0-100)
        AirLCD_1000.setBacklight(5)  -- 设置背光为5%
        sys.wait(5000)
        AirLCD_1000.setBacklight(10)  -- 设置背光为10%
        sys.wait(5000)
        AirLCD_1000.setBacklight(20)  -- 设置背光为20%
        sys.wait(5000)
        AirLCD_1000.setBacklight(30)  -- 设置背光为30%
        sys.wait(5000)
        AirLCD_1000.setBacklight(40)  -- 设置背光为40%
        sys.wait(5000)
        AirLCD_1000.setBacklight(50)  -- 设置背光为50%
        sys.wait(5000)
        AirLCD_1000.setBacklight(60)  -- 设置背光为60%
        sys.wait(5000)
        AirLCD_1000.setBacklight(70)  -- 设置背光为70%
        sys.wait(5000)
        AirLCD_1000.setBacklight(80)  -- 设置背光为80%
        sys.wait(5000)
        AirLCD_1000.setBacklight(90)  -- 设置背光为90%
        sys.wait(5000)
        AirLCD_1000.setBacklight(100)  -- 设置背光为100%

        --------------------------------------------以下为屏幕休眠设置--------------------------------------------
        -- 背光引脚使用GPIO引脚控制，且screen_data_table{}内pin_pwr正确配置可以实现背光控制

        -- 进入休眠，功耗13ma
        AirLCD_1000.setSleep(true)    -- 进入休眠状态，此时屏幕供电需要稳定，若不稳定，唤醒后需要重新初始化屏幕
        sys.wait(10000)

        AirLCD_1000.setSleep(false)   -- 唤醒屏幕，自动恢复之前的背光设置

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
end)

return ui_main