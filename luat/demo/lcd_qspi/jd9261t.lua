-- 必须在task里用
function jd9261t_init(lcd_cfg)
    lcd.qspi(0xde, 0xde, nil, 0x61, 0xde, 0x60)
    lcd.init("user", lcd_cfg) 
    gpio.set(lcd_cfg.pin_rst, 0)
    gpio.set(lcd_cfg.pin_pwr, 0)
    sys.wait(5)
    gpio.set(lcd_cfg.pin_rst, 1)
    sys.wait(200)
    lcd.cmd(0x36, 0x00) --方向
    gpio.set(lcd_cfg.pin_pwr, 1)
end