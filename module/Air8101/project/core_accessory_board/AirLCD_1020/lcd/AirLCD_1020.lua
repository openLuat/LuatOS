local AirLCD_1020 = {}

local WIDTH, HEIGHT = 800, 480


-- 初始化AirLCD_1020的LCD配置
function AirLCD_1020.init_lcd()
    -- st7265
    lcd.init("custom",
        {port = lcd.RGB, hbp = 8, hspw = 4, hfp = 8, vbp = 16, vspw = 4, vfp = 16,
        bus_speed = 30*1000*1000, direction = 0, w = WIDTH, h = HEIGHT, xoffset = 0, yoffset = 0})
end

-- 关闭AirLCD_1020的LCD
function AirLCD_1020.close_lcd()
    lcd.close()
end




-- 初始化AirLCD_1020的TP配置
-- 无论使用硬件i2c还是软件io模拟i2c，都是传入引脚的GPIO ID
-- int：中断引脚GPIO ID，如果为空，默认会使用7
-- rst：复位控制引脚GPIO ID，如果为空，默认会使用28
-- sda：数据引脚GPIO ID，如果为空，默认会使用1
-- scl：时钟引脚GPIO ID，如果为空，默认会使用0
function AirLCD_1020.init_tp(int, rst, sda, scl, cb)
    local i2cPort = i2c.createSoft(scl or 0, sda or 1)  

    AirLCD_1020.tp_device = tp.init("gt911",{port=i2cPort, pin_rst = rst or 28, pin_int = int or 7, w = WIDTH, h = HEIGHT}, cb)

    return AirLCD_1020.tp_device
end


-- 打开AirLCD_1020的背光
-- gpio_id：控制背光的GPIO ID，如果为空，默认会使用8
function AirLCD_1020.open_backlight(gpio_id)
    gpio.setup(gpio_id or 8, 1)
end

-- 关闭AirLCD_1020的背光
-- gpio_id：控制背光的GPIO ID，如果为空，默认会使用8
function AirLCD_1020.close_backlight(gpio_id)
    gpio.setup(gpio_id or 8, 0)
end



return AirLCD_1020
