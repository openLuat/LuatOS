PROJECT = "lcddemo"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

taskName = "lcd"
local airlcd = require "airlcd"


show_picture = "/luadb/picture.jpg"

local function lcd_setup()
    sys.wait(500)
    gpio.setup(141, 1, gpio.PULLUP)              -- 如果是整机开发板则需要GPIO141打开给lcd电源供电，如果是核心板，可以自行选择供电管脚，或者直接选择vdd_ext管脚
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
            log.info("picture.jpg 不存在，请检查下载的文件")
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




-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
