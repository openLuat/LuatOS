--[[
1.本demo可直接在Air8000整机开发板上运行，如有需要请luat.taobao.com 购买
2.注意
    2.1 本demo 不可以和camera 教程同时使用，因为该demo 使用了LCD 的所有管脚，会产生冲突
    2.2 需要下载本demo路径下的resource里面的logo.jpg文件，如果不下载将不显示图片内容
3.使用了如下的IO口，请在pins_Air8000.json 上配置
    [25, "LCD_CLK", " PIN25脚, LCD 时钟"],
    [26, "LCD_CS", " PIN26脚, LCD 片选"],
    [27, "LCD_RST", " PIN27脚, LCD 复位控制"],
    [28, "LCD_SDA", " PIN28脚, LCD 数据传输"],
    [29, "LCD_RS", " PIN29脚, LCD 的信号指令"],
    [30, "GPIO2", " PIN30脚, QSPI 时候作为信号传输"],
    [31, "GPIO1", " PIN31脚, QSPI 时候作为信号传输"],
    [44, "WAKEUP0", " PIN44脚, 触摸屏中断脚"],  
    [55, "GPIO141", " PIN55脚, 用于控制LCD 使能"],
    [80, "I2C0_SCL", " PIN80脚, I2C0_SCL 触摸屏通信,摄像头复用"],
    [81, "I2C0_SDA", " PIN81脚, I2C0_SDA 触摸屏通信,摄像头复用"],
4.程序运行逻辑为，选择你需要的屏幕，程序运行后将在LCD 上显示logo.jpg，
]]

taskName = "lcd"
--[[
"LCM_1111":                ---  480*320 不支持触摸
"LCM_1112":                ---  480*320 支持触摸
"LCM_2231":                ---  480*480 支持触摸
]]
local airlcd = require "airlcd"


show_picture = "/luadb/logo.jpg"

local function lcd_setup()
    sys.wait(500)
    gpio.setup(141, 1)              -- GPIO141打开给lcd电源供电 
    sys.wait(1000)
    airlcd.lcd_init("AirLCD_1000")
end


local function lcd_task()
    lcd_setup()                     -- 初始化LCD
    lcd.setupBuff(nil, true)        -- 设置缓冲区大小，使用系统内存
    lcd.autoFlush(false)            -- 自动刷新LCD
    while 1 do
        lcd.clear()
        log.info("合宙 Air8000 LCD演示")
        -- API 文档 https://wiki.luatos.com/api/lcd.html
        if io.exists(show_picture) ~= true then
            log.info("logo.jpg 不存在，请检查下载的文件")
            sys.wait(100)
            return
        end 

        -- 注意, jpg需要是常规格式, 不能是渐进式JPG
        -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
        lcd.showImage(0, 0, show_picture)
        sys.wait(100)
       
        -- log.info("lcd.drawLine", lcd.drawLine(100, 240, 240, 240, 0x001F)) -- 画线
        -- log.info("lcd.drawRectangle", lcd.drawRectangle(100, 240, 240, 70, 0xF800)) -- 画框
        -- log.info("lcd.drawCircle", lcd.drawCircle(150, 240, 100, 0x0CE0)) -- 画圆

        -- lcd.setFont(lcd.font_opposansm32)
        -- lcd.drawStr(60,240,"hello hezhou") --显示字符
        lcd.flush()
        sys.wait(1000)
    end
end


sysplus.taskInitEx(lcd_task, taskName)   


