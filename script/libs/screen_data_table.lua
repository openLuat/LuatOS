-- screen_data_table.lua )
-- 此文件只包含屏幕相关配置数据

local screen_data_table = {
    lcdargs = {
        LCD_MODEL = "AirLCD_1001",
        pin_vcc = 24,
        pin_rst = 36,
        pin_pwr = 25,
        pin_pwm = 2,
        port = lcd.HWID_0,
        direction = 0,
        w = 320,
        h = 480,
        xoffset = 0,
        yoffset = 0,
    },
    touch = {
        TP_MODEL = "Air780EHM_LCD_4", -- 触摸芯片型号
        i2c_id = 1,               -- I2C总线ID
        pin_rst = 255,              -- 触摸芯片复位引脚(非必须)
        pin_int = 22              -- 触摸芯片中断引脚
    },
}

return screen_data_table
