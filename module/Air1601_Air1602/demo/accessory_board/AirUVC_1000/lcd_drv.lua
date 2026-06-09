local port, pin_reset, bl = lcd.RGB, 15, 2

local function lcd_drv_init()
    local result = lcd.init("custom", {
        port = port,
        hbp = 140,
        hspw = 20,
        hfp = 160,
        vbp = 20,
        vspw = 3,
        vfp = 12,
        bus_speed = 50 * 1000 * 1000,
        pin_pwr = bl,
        pin_rst = pin_reset,
        direction = 0,
        w = 1024,
        h = 600,
        clk_polarity = 1
    })

    log.info("lcd.init", result)

    if result then
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)
        
        lcd.clear(0x001F)
        lcd.drawStr(250, 250, "LCD初始化成功", 0xFFFF)
        lcd.flush()

        return result
    else
        log.error("lcd_drv", "LCD初始化失败")
        return result
    end
end

local init_result = lcd_drv_init()
log.info("lcd_drv", "初始化结果", init_result)
