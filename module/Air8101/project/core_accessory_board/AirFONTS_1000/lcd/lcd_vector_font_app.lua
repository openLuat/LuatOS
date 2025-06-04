--加载AirFONTS_1000驱动文件
local air_vetor_fonts = require "AirFONTS_1000"
--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"


--lcd显示矢量字体的task
--自动刷新显示不同字号矢量字体以及不同bit的灰度显示效果
local function lcd_vector_font_app_task_func()
    log.info("lcd_vector_font_app_task_func enter")
    -- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
    -- 第一个参数无意义，直接填nil即可
    -- 第二个参数true表示使用sys中的内存
    lcd.setupBuff(nil, true)
    --禁止自动刷新
    --需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
    lcd.autoFlush(false)

    --每隔10秒清屏并且全屏刷新显示一张图片
    while true do
        --清屏
        lcd.clear()

        lcd.setColor(0xFFFF, 0x0000)
        lcd.drawGtfontUtf8("AirFONTS_1000",32,240,150)
        lcd.drawGtfontUtf8Gray("配件板",32,4,444,150)

        lcd.setColor(0xFFFF, 0xF800)
        lcd.drawGtfontUtf8Gray("支持",32,4,224-8,191)
        lcd.drawGtfontUtf8("16",32,288-8,191)
        lcd.drawGtfontUtf8Gray("到",32,4,320-8,191)
        lcd.drawGtfontUtf8("192",32,352-8,191)
        lcd.drawGtfontUtf8Gray("号的黑体字体",32,4,384+3,191)

        lcd.setColor(0xFFFF, 0x07E0)
        lcd.drawGtfontUtf8Gray("支持",32,4,192-10,232)
        lcd.drawGtfontUtf8("GBK",32,256-10,232)
        lcd.drawGtfontUtf8Gray("中文和",32,4,324-10,232)
        lcd.drawGtfontUtf8("ASCII",32,420-10,232)
        lcd.drawGtfontUtf8Gray("码字符集",32,4,500-10,232)

        lcd.setColor(0xFFFF, 0x001F)
        lcd.drawGtfontUtf8Gray("支持灰度显示，字体边缘更平滑",32,4,176,273)

        -- lcd.flush()


        -- for i=16,32,2 do
        --     lcd.clear()
        --     lcd.drawGtfontUtf8(i.."号：合宙Air8101   LuatOS",i,10,10)
        --     lcd.flush()
        --     sys.wait(1000)
        -- end

        --灰度1：16 24 32
        --灰度2：16 24 32
        --灰度3：16 32
        --灰度4：16 20 24 28 32
        -- for i=16,32,2 do
        --     lcd.clear()
        --     lcd.drawGtfontUtf8Gray(i.."号灰度4：合宙Air8101 LuatOS",i,4,10,10)
        --     lcd.flush()
        --     sys.wait(1000)
        -- end
       
        -- lcd.drawGtfontUtf8("16号：合宙Air8101 LuatOS",16,10,10)
        -- lcd.drawGtfontUtf8("20号：合宙Air8101 LuatOS",20,10,30)
        -- lcd.drawGtfontUtf8("24号：合宙Air8101 LuatOS",24,10,54)
        -- lcd.drawGtfontUtf8("28号：合宙Air8101 LuatOS",28,10,82)
        -- lcd.drawGtfontUtf8("32号：合宙Air8101 LuatOS",32,10,114)
        -- lcd.drawGtfontUtf8("36号：合宙Air8101 LuatOS",36,10,150)
        -- lcd.drawGtfontUtf8("40号：合宙Air8101 LuatOS",40,10,190)
        -- lcd.drawGtfontUtf8("44号：合宙Air8101 LuatOS",44,10,234)
        -- lcd.drawGtfontUtf8("48号：合宙Air8101 LuatOS",48,10,282)
        -- lcd.drawGtfontUtf8("64号：合宙Air8101 LuatOS",64,10,334)

        -- lcd.drawGtfontUtf8("合宙Air8101 LuatOS",12,0,100)
        -- lcd.drawGtfontUtf8Gray("啊啊啊",32,4,0,140)
        --刷屏，将缓冲区中的数据显示到lcd上
        lcd.flush()
        --等待10秒钟
        sys.wait(1000000)
    end
end


--初始化矢量字库
air_vetor_fonts.init()

--初始化LCD
air_lcd.init_lcd()
--打开LCD背光
air_lcd.open_backlight()

--创建并且启动一个task
--task的主函数为lcd_vector_font_app_task_func
sys.taskInit(lcd_vector_font_app_task_func)

