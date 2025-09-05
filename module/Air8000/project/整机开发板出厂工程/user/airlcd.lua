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

    spi.deviceSetup(
            lcd.HWID_0,  -- LCD端口号
            nil,         -- CS片选脚，可选
            0,           -- CPHA=0
            0,           -- CPOL=0
            8,           -- 8位数据宽度
            20000000,    -- 20MHz波特率
            spi.MSB,     -- 高位先传
            1,           -- 主机模式
            1            -- 全双工模式
        )
    gpio.setup(164, 1, gpio.PULLUP)
    gpio.setup(141, 1, gpio.PULLUP)
    -- 设置DC和RST引脚为输出模式，并启用上拉电阻
    gpio.setup(lcd_param.pin_dc, 1, gpio.PULLUP)
    gpio.setup(lcd_param.pin_rst, 1, gpio.PULLUP)
    
    -- 设置DC引脚为高电平(数据模式)
    gpio.set(lcd_param.pin_dc, 1)

    -- 执行复位序列
    gpio.set(lcd_param.pin_rst, 0)  -- 拉低复位引脚
    sys.wait(20)                    -- 等待20ms(ST7796复位拉低大于10ms生效)
    gpio.set(lcd_param.pin_rst, 1)  -- 拉高复位引脚
    sys.wait(150)                   -- 等待150ms(ST7796复位拉高大于120ms重置)
    
    -- 初始化ST7796显示芯片
    lcd.init(lcd_ic, lcd_param)

    lcd.setupBuff(nil, true)        -- 设置缓冲区大小，使用系统内存
    lcd.autoFlush(false)            -- 自动刷新LCD

    if sn == "AirLCD_1001"  then
        log.info("tp", "tp init")
        local function tp_callBack(tp_device,tp_data)
            sys.publish("TP",tp_device,tp_data)
        end

        local i2c_id = 0
        i2c.setup(i2c_id, i2c.SLOW)
        tp_device = tp.init("gt911",{port=i2c_id, pin_rst = 20,pin_int = gpio.WAKEUP0,},tp_callBack)
    end

end

return airLCD