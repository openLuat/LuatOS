local air_ui = {}

function air_ui.lcd_init()
    log.info("lcd", "lcd init")
    local LCD_power = gpio.setup(141, 1, gpio.PULLUP)

    local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd.HWID_0, 36, 0xff, 0xff, 25
    lcd.init("st7796", {
        port = spi_id,
        pin_dc = pin_dc,
        pin_pwr = bl,
        pin_rst = pin_reset,
        w = 480,
        h = 320,
        direction =1,
        xoffset = 0,
        yoffset = 0
    })
    log.info("lcd", "lcd init end")
    -- -- lcd反显
    -- lcd.invon()
    lcd.setFont(lcd.font_opposansm12_chinese) -- 设置中文字体
end

local function display(x1, y1, x2, y2, buffer)

end

-- 刷屏函数
function air_ui.refresh()
    log.info("刷屏")
    lcd.setupBuff(nil, true)
    lcd.autoFlush(false)
    lcd.clear()
    lcd.flush()
end

return air_ui
