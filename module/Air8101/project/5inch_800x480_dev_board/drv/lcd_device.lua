local lcd_device = 
{
    width = 800,
    height = 480,
    -- bg_color = 0x10E3, -- 星空黑
    fg_color = 0xDEF7, -- 灰白
    -- fg_color = 0x2759, -- 亮蓝
    bg_color = 0x2124,
    -- fg_color = 0xDC60, -- 暗黑金
    
}

--加载AirFONTS_1000驱动文件
local air_vetor_fonts = require "AirFONTS_1000"
--加载AirLCD_1020驱动文件
local air_lcd = require "AirLCD_1020"
--TP设备
local tp_device

local function tp_callback(tp_device,tp_data)
    -- log.info("tp_callback", tp_data[1].event, tp_data[1].x, tp_data[1].y, tp_data[1].timestamp, mcu.hz())
    sys.publish("LIBWIN_TOUCH", tp_data)
    -- sys.publish("TP", tp_device, tp_data)
end

-- 整机开发板上矢量字库供电使能控制引脚为GPIO32
-- 需要GPIO32输出高电平，打开使能控制
gpio.setup(32, 1)
mcu.altfun(mcu.SPI, 0, 33)
mcu.altfun(mcu.SPI, 0, 34)
mcu.altfun(mcu.SPI, 0, 35)
mcu.altfun(mcu.SPI, 0, 36)
--初始化矢量字库，使用GPIO33到GPIO36四个引脚
air_vetor_fonts.init(0, 34)

-- 整机开发板上LCD供电使能控制引脚为GPIO5
-- 需要GPIO5输出高电平，打开使能控制
gpio.setup(5, 1)
--初始化LCD
air_lcd.init_lcd()
--初始化TP触摸面板，触摸事件的回调函数为tp_callback
air_lcd.init_tp(nil, nil, nil, nil, tp_callback)
--打开LCD背光
air_lcd.open_backlight()

-- 开启显示缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存(2*宽*高 字节)
-- 第一个参数无意义，直接填nil即可
-- 第二个参数true表示使用sys中的内存
lcd.setupBuff(nil, true)
--禁止自动刷新
--需要刷新时需要主动调用lcd.flush()接口，才能将缓冲区中的数据显示到lcd上
lcd.autoFlush(false)

return lcd_device