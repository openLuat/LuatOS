local airLCD = {}

function airLCD.lcd_init(sn)
    if sn == "AirLCD_1000" then
        width = 320
        height = 480
        lcd_ic = "st7796"
    elseif sn == "AirLCD_1001" then
        width = 320
        height = 480
        lcd_ic = "st7796"
    elseif  sn == "AirLCD_1002" then
        width = 480
        height = 480
        lcd_ic = "R395435T01"
    else
        log.info("lcd", "没有找到合适的LCD")
    end

    lcd_param = {
        port = lcd.HWID_0,                 -- 使用的spi id 号
        pin_dc = 0xff,            -- 命令选择硬件，不设置
        pin_pwr = 9,           -- 背光控制管脚，默认打开背光，不设置
        pin_rst = 2,             -- 屏幕reset 管脚  
        direction = 0,            -- 屏幕方向
        -- direction0 = 0x00,
        w = width,                -- 屏幕宽度
        h = height,               -- 屏幕高度
        xoffset = 0,              -- X轴偏移像素
        yoffset = 0,              -- Y轴偏移像素
        sleepcmd = 0x10,          -- LCD睡眠命令
        wakecmd = 0x11,           -- LCD唤醒命令
    
    }
    
 
    lcd.init(lcd_ic, lcd_param)     -- 初始化LCD 参数
end



return airLCD