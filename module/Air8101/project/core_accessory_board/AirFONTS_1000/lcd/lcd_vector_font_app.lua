--加载AirFONTS_1000驱动文件
local air_vetor_fonts = require "AirFONTS_1000"
--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"


--lcd显示矢量字体的task
--自动刷新显示16到192字号的字体显示效果（非灰度显示以及灰度显示）
local function lcd_vector_font_app_task_func()
    log.info("lcd_vector_font_app_task_func enter")
    -- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
    -- 第一个参数无意义，直接填nil即可
    -- 第二个参数true表示使用sys中的内存
    lcd.setupBuff(nil, true)
    --禁止自动刷新
    --需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
    lcd.autoFlush(false)

    while true do
        -- 显示AirFONTS_1000的总体特性
        -- 目前还有两个问题：
        -- 1、字母显示宽度不正常
        -- 2、颜色设置接口还没生效
        for i=15,1,-1 do
            --清屏
            lcd.clear()

            --设置背景色为白色，文字的前景色为黑色
            lcd.setColor(0xFFFF, 0x0000)
            lcd.drawGtfontUtf8("AirFONTS_1000配件板",32,240,150)

            --设置背景色为白色，文字的前景色为红色
            lcd.setColor(0xFFFF, 0xF800)
            lcd.drawGtfontUtf8("支持16到192号的黑体字体",32,224-8,191)

            --设置背景色为白色，文字的前景色为绿色
            lcd.setColor(0xFFFF, 0x07E0)
            lcd.drawGtfontUtf8("支持GBK中文和ASCII码字符集",32,192-10,232)

            --设置背景色为白色，文字的前景色为蓝色
            lcd.setColor(0xFFFF, 0x001F)
            lcd.drawGtfontUtf8("支持灰度显示，字体边缘更平滑",32,176,273)
        
            lcd.drawGtfontUtf8("倒计时："..i,32,320,313)

            --刷屏显示
            lcd.flush()

            --等待1秒
            sys.wait(1000)
        end

        -- 16号到192号不支持灰度的显示效果演示

        --设置背景色为白色，文字的前景色为黑色
        lcd.setColor(0xFFFF, 0x0000)
        for i=16,64,1 do
            --清屏
            lcd.clear()

            lcd.drawGtfontUtf8(i.."号：合宙Air8101 LuatOS",i,10,10)

            --刷屏显示
            lcd.flush()

            --等待100毫秒
            sys.wait(100)
        end

        --设置背景色为白色，文字的前景色为红色
        lcd.setColor(0xFFFF, 0xF800)
        for i=65,96,1 do
            --清屏
            lcd.clear()

            lcd.drawGtfontUtf8(i.."号",i,10,10)
            lcd.drawGtfontUtf8("合宙Air8101 LuatOS",i,10,10+i+5)

            --刷屏显示
            lcd.flush()

            --等待100毫秒
            sys.wait(100)
        end

        --设置背景色为白色，文字的前景色为绿色
        lcd.setColor(0xFFFF, 0x07E0)
        for i=97,128,1 do
            --清屏
            lcd.clear()

            lcd.drawGtfontUtf8(i.."号",i,10,10)
            lcd.drawGtfontUtf8("合宙",i,10,10+i+5)

            --刷屏显示
            lcd.flush()

            --等待100毫秒
            sys.wait(100)
        end

        -- 还有错误，不能显示
        --设置背景色为白色，文字的前景色为蓝色
        -- lcd.setColor(0xFFFF, 0x001F)
        -- for i=129,192,1 do
        --     --清屏
        --     lcd.clear()

        --     lcd.drawGtfontUtf8(i.."号",i,10,10)
        --     lcd.drawGtfontUtf8("合宙",i,10,10+i+5)

        --     --刷屏显示
        --     lcd.flush()

        --     --等待100毫秒
        --     sys.wait(100)
        -- end


        -- 16号到192号支持灰度的显示效果演示

        --设置背景色为白色，文字的前景色为黑色
        lcd.setColor(0xFFFF, 0x0000)
        for i=16,48,1 do
            --清屏
            lcd.clear()
            lcd.drawGtfontUtf8Gray(i.."号灰度：合宙Air8101 LuatOS",i,4,10,10)

            --刷屏显示
            lcd.flush()

            --等待100毫秒
            sys.wait(100)
        end

        --设置背景色为白色，文字的前景色为红色
        lcd.setColor(0xFFFF, 0xF800)
        for i=49,80,1 do
            --清屏
            lcd.clear()
            lcd.drawGtfontUtf8Gray(i.."号灰度",i,4,10,10)
            lcd.drawGtfontUtf8Gray("合宙Air8101 LuatOS",i,4,10,10+i+5)

            --刷屏显示
            lcd.flush()

            --等待100毫秒
            sys.wait(100)
        end

        --设置背景色为白色，文字的前景色为绿色
        lcd.setColor(0xFFFF, 0x07E0)
        for i=81,128,1 do
            --清屏
            lcd.clear()
            lcd.drawGtfontUtf8Gray(i.."号",i,4,10,10)
            lcd.drawGtfontUtf8Gray("合宙",i,4,10,10+i+5)

            --刷屏显示
            lcd.flush()

            --等待100毫秒
            sys.wait(100)
        end

        -- 还有错误，不能显示
        --设置背景色为白色，文字的前景色为蓝色
        -- lcd.setColor(0xFFFF, 0x001F)
        -- for i=129,192,1 do
        --     --清屏
        --     lcd.clear()

        --     lcd.drawGtfontUtf8(i.."号",i,10,10)
        --     lcd.drawGtfontUtf8("合宙",i,10,10+i+5)

        --     --刷屏显示
        --     lcd.flush()
        --     sys.wait(100)
        -- end

        --等待1秒钟
        sys.wait(1000)
    end
end


-- mcu.altfun(mcu.SPI,0,33)
-- mcu.altfun(mcu.SPI,0,34)
-- mcu.altfun(mcu.SPI,0,35)
-- mcu.altfun(mcu.SPI,0,36)

--初始化矢量字库
-- air_vetor_fonts.init()
air_vetor_fonts.init(0, 34)

--初始化LCD
air_lcd.init_lcd()
--打开LCD背光
air_lcd.open_backlight()

--创建并且启动一个task
--task的主函数为lcd_vector_font_app_task_func
sys.taskInit(lcd_vector_font_app_task_func)

