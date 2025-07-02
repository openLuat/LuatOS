-- 必须在task里用
function sh8601z_init(lcd_cfg)
    lcd.qspi(0x02, 0x32, 0x12)
    lcd.init("user", lcd_cfg) 
    gpio.set(lcd_cfg.pin_rst, 0)
    sys.wait(20)
    gpio.set(lcd_cfg.pin_rst, 1)
    sys.wait(50)
    lcd.wakeup()
    sys.wait(100)
    -- 演示一下用zbuff传参数，和下面的直接传参数是等效的
    local param = zbuff.create(1)
    param[0] = 0x00
    lcd.cmd(0x36, param, 1) --方向
    param[0] = 0x55
    lcd.cmd(0x3a, param, 1)
    param[0] = 0x20
    lcd.cmd(0x53, param, 1)
    param[0] = 0xff
    lcd.cmd(0x51, param, 1)

    -- lcd.cmd(0x36, 0x00) --方向
    -- lcd.cmd(0x3a, 0x55)
    -- lcd.cmd(0x53, 0x20)
    -- lcd.cmd(0x51, 0xff)
    lcd.cmd(0x29)
end