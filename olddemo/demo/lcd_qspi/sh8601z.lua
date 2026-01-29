-- 必须在task里用,自发光屏幕不需要背光控制
function sh8601z_init(lcd_cfg)
    lcd.qspi(0x02, 0x32, 0x12)
    lcd.init("user", lcd_cfg) 
    gpio.set(lcd_cfg.pin_rst, 0)
    sys.wait(20)
    gpio.set(lcd_cfg.pin_rst, 1)
    sys.wait(50)
    lcd.wakeup()
    sys.wait(100)

    local param = zbuff.create(2)

    lcd.cmd(0x36, 0x00) --方向
    lcd.cmd(0x3a, 0x55)
    lcd.cmd(0x53, 0x20)
    lcd.cmd(0x51, 0xff)
	param[0] = 0x5a
	param[1] = 0x5a
	lcd.cmd(0xc0, param, 2) --2个字节以上的参数必须用zbuff
	lcd.cmd(0xc1, param, 2)
	lcd.cmd(0xb0, 0x33)
	lcd.cmd(0xb1, 0x02)
    lcd.cmd(0x29)
end