---------------------------------------------功能说明---------------------------------------------
--[[
本文件为用户界面主模块
核心功能：
1. 协调各UI子文件
2. 初始化显示、触摸和页面管理
3. 管理主循环和事件分发

执行流程：
1. 初始化矢量字库
2. 初始化显示屏
3. 进入主循环显示
]]
---------------------------------------------相关代码---------------------------------------------
local ui_main = {}

--加载AirFONTS_1000驱动文件
local air_vetor_fonts = require "AirFONTS_1000"
--加载AirLCD_1001驱动文件
local airlcd = require "airlcd"           -- LCD驱动
local LCD_MODEL = "AirLCD_1001"           -- LCD型号
local spi_id = 0 -- 接到模组的spi端口号，sip0就写0，spi1就写1
local spi_cs = 8 -- 字库所借spi片选引脚所对应的GPIO端口号

-- lcd显示矢量字体的task
-- AirFONTS_1000矢量字库，使用gtfont灰度显示UTF8字符串，支持16-192号大小字体
-- 自动刷新显示16到192字号的字体显示效果（非灰度显示以及灰度显示）

sys.taskInit(function()
    -- 初始化外置AirFONTS_1000矢量字库，使用gtfont灰度显示UTF8字符串，支持16-192号大小字体
    air_vetor_fonts.init(spi_id,spi_cs)       --设置初始化AirFONTS_1000矢量字体
    lcd.setFont(lcd.drawGtfontUtf8)           --设置使用高通矢量字体

    -- 按所配置的型号参数初始化显示屏
    -- 注意：在airlcd内是按核心板和AirLCD_1001参数设置的，实际使用过程中按实际参数在airlcd和page_data_table内修改配置。
    airlcd.lcd_init(LCD_MODEL)

-- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
    -- 第一个参数无意义，直接填nil即可
    -- 第二个参数true表示使用sys中的内存
    --lcd.setupBuff(nil, true)
    --禁止自动刷新
    --需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
    --lcd.autoFlush(false)

    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)

    while true do
        -- 显示AirFONTS_1000的总体特性
        -- 目前还有两个问题：
        -- 1、字母显示宽度不正常
        -- 2、颜色设置接口还没生效
        for i=5,1,-1 do
            --清屏
            lcd.clear()

            --设置背景色为白色，文字的前景色为黑色
            lcd.setColor(0xFFFF, 0x0000)
            lcd.drawGtfontUtf8("AirFONTS_1000配件板",32,50,50)

            --设置背景色为白色，文字的前景色为红色
            lcd.setColor(0xFFFF, 0xF800)
            lcd.drawGtfontUtf8("支持16到192号的黑体字体",32,50-8,91)

            --设置背景色为白色，文字的前景色为绿色
            lcd.setColor(0xFFFF, 0x07E0)
            lcd.drawGtfontUtf8("支持GBK中文和ASCII码字符集",32,50-20,132)

            --设置背景色为白色，文字的前景色为蓝色
            lcd.setColor(0xFFFF, 0x001F)
            lcd.drawGtfontUtf8("支持灰度显示，字体边缘更平滑",32,20,173)
        
            lcd.drawGtfontUtf8("倒计时："..i,32,150,213)

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

            lcd.drawGtfontUtf8(i.."号：合宙AirFONTS_1000",i,60,100)

            --刷屏显示
            lcd.flush()

            --等待20毫秒
            sys.wait(20)
        end

        --设置背景色为白色，文字的前景色为红色
        lcd.setColor(0xFFFF, 0xF800)
        for i=65,96,1 do
            --清屏
            lcd.clear()

            lcd.drawGtfontUtf8(i.."号",i,60,100)
            lcd.drawGtfontUtf8("AirFONTS_1000",i,60,100+i+5)

            --刷屏显示
            lcd.flush()

            --等待20毫秒
            sys.wait(20)
        end

        --设置背景色为白色，文字的前景色为绿色
        lcd.setColor(0xFFFF, 0x07E0)
        for i=97,128,1 do
            --清屏
            lcd.clear()

            lcd.drawGtfontUtf8(i.."号",i,60,20)
            lcd.drawGtfontUtf8("合宙",i,60,20+i+5)

            --刷屏显示
            lcd.flush()

            --等待20毫秒
            sys.wait(20)
        end

        --设置背景色为白色，文字的前景色为蓝色
        lcd.setColor(0xFFFF, 0x001F)
        for i=129,192,1 do
            --清屏
            lcd.clear()

            lcd.drawGtfontUtf8(i.."号",i,60,20)
            lcd.drawGtfontUtf8("合宙",i,60,20+i+5)

            --刷屏显示
            lcd.flush()

            --等待20毫秒
            sys.wait(20)
        end

        -- 16号到192号支持灰度的显示效果演示

        --设置背景色为白色，文字的前景色为黑色
        lcd.setColor(0xFFFF, 0x0000)
        for i=16,48,1 do
            --清屏
            lcd.clear()
            lcd.drawGtfontUtf8Gray(i.."号灰度：合宙AirFONTS_1000",i,4,60,100)

            --刷屏显示
            lcd.flush()

            --等待20毫秒
            sys.wait(20)
        end

        --设置背景色为白色，文字的前景色为红色
        lcd.setColor(0xFFFF, 0xF800)
        for i=49,80,1 do
            --清屏
            lcd.clear()
            lcd.drawGtfontUtf8Gray(i.."号灰度",i,4,60,100)
            lcd.drawGtfontUtf8Gray("合宙AirFONTS_1000",i,4,60,100+i+5)

            --刷屏显示
            lcd.flush()

            --等待20毫秒
            sys.wait(20)
        end

        --设置背景色为白色，文字的前景色为绿色
        lcd.setColor(0xFFFF, 0x07E0)
        for i=81,128,1 do
            --清屏
            lcd.clear()
            lcd.drawGtfontUtf8Gray(i.."号",i,4,60,20)
            lcd.drawGtfontUtf8Gray("合宙",i,4,60,20+i+5)

            --刷屏显示
            lcd.flush()

            --等待20毫秒
            sys.wait(20)
        end
        --设置背景色为白色，文字的前景色为蓝色
        lcd.setColor(0xFFFF, 0x001F)
        for i=129,192,1 do
            --清屏
            lcd.clear()

            lcd.drawGtfontUtf8(i.."号",i,60,20)
            lcd.drawGtfontUtf8("合宙",i,60,20+i+5)

            --刷屏显示
            lcd.flush()
            sys.wait(20)
        end
    end
end)

return ui_main