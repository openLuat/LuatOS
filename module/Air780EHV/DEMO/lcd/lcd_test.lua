--[[
@module  lcd_test
@summary lcd_test测试功能模块
@version 1.0
@date    2025.07.01
@author  yc
@usage
使用Air780EHV核心板 配合 ST7796 LCD 显示屏幕演示基本的显示功能.
]]


-- 根据不同的BSP返回不同的值
-- spi_id,pin_reset,pin_dc,pin_cs,bl
local function lcd_pin()
    local rtos_bsp = rtos.bsp()
    if string.find(rtos_bsp, "780EHV") then
        return lcd.HWID_0, 36, 0xff, 0xff, 25
    else
        log.info("main", "没找到合适的cat.1芯片", rtos_bsp)
        return
    end
end


function lcd_test_func()

    local spi_id, pin_reset, pin_dc, pin_cs, bl = lcd_pin()
    if spi_id ~= lcd.HWID_0 then
        spi_lcd = spi.deviceSetup(spi_id, pin_cs, 0, 0, 8, 20 * 1000 * 1000, spi.MSB, 1, 0)
        port = "device"
    else
        port = spi_id
    end

    lcd.init("st7796", {
    port = port,
    pin_dc = pin_dc,
    pin_pwr = bl,
    pin_rst = pin_reset,
    direction = 0,

    w = 320,
    h = 480,
    xoffset = 0,
    yoffset = 0,
    sleepcmd = 0x10,
    wakecmd = 0x11,
    })


    -- 开启缓冲区, 刷屏速度回加快, 但也消耗2倍屏幕分辨率的内存
    -- lcd.setupBuff()          -- 使用lua内存
    lcd.setupBuff(nil, true) -- 使用sys内存, 只需要选一种
    lcd.autoFlush(false)

    while 1 do
        lcd.clear()
        log.info("图片显示")
        -- API 文档 https://wiki.luatos.com/api/lcd.html
        if lcd.showImage then
            -- 注意, jpg需要是常规格式, 不能是渐进式JPG
            -- 如果无法解码, 可以用画图工具另存为,新文件就能解码了
            lcd.showImage(0, 0, "/luadb/picture.jpg")
            sys.wait(100)
        end
        lcd.flush()
        sys.wait(3000)
        --lcd清屏
        lcd.clear()

        -- 画线
        log.info("lcd.drawLine", lcd.drawLine(100, 240, 240, 240, 0x001F))
        lcd.flush()
        sys.wait(3000)
        --lcd清屏
        lcd.clear()

        -- 画框
        log.info("lcd.drawRectangle", lcd.drawRectangle(100, 240, 240, 70, 0xF800))
        lcd.flush()
        sys.wait(3000)
        --lcd清屏
        lcd.clear()

        -- 画圆
        log.info("lcd.drawCircle", lcd.drawCircle(150, 240, 100, 0x0CE0))
        lcd.flush()
        sys.wait(3000)
        --lcd清屏
        lcd.clear()

        lcd.setFont(lcd.font_opposansm32)
        lcd.drawStr(60,240,"hello hezhou") --显示字符
        lcd.flush()
        sys.wait(3000)
        --lcd清屏
        lcd.clear()

    end
end
--创建并且启动一个task
--运行这个task的主函数lcd_test_func
sys.taskInit(lcd_test_func)
