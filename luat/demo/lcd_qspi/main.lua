PROJECT = "lcd_qspi"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

require "co5300"
require "jd9261t"
require "sh8601z"

sys.taskInit(function()

    local test_cnt = 0
    pm.ioVol(0, 3300)
    gpio.setup(20,1)    --打开sh8601z LCD电源，根据板子实际情况修改
    gpio.setup(16,1)    --打开jd9261t LCD电源，根据板子实际情况修改
    gpio.setup(17,1)    --打开co5300 LCD电源，根据板子实际情况修改

    co5300_init({port = lcd.HWID_0, pin_dc = -1, pin_pwr = -1, pin_rst = 36, w = 480, h = 480, interface_mode=lcd.QSPI_MODE,bus_speed=50000000, rb_swap = true})
    -- jd9261t_init({port = lcd.HWID_0,pin_dc = -1, pin_pwr = 27, pin_rst = 36, w = 480,h = 480, interface_mode=lcd.QSPI_MODE, bus_speed=60000000,flush_rate=659,vbp=19,vfp=108,vs=2,rb_swap=true})
    -- jd9261t_init({port = lcd.HWID_0,pin_dc = -1, pin_pwr = 27, pin_rst = 36, w = 540,h = 540, interface_mode=lcd.QSPI_MODE, bus_speed=80000000,flush_rate=600,vbp=10,vfp=108,vs=2,rb_swap=true})
    -- jd9261t_init({port = lcd.HWID_0,pin_dc = -1, pin_pwr = 27, pin_rst = 36, w = 720,h = 720, interface_mode=lcd.QSPI_MODE, bus_speed=60000000,flush_rate=300,vbp=10,vfp=160,vs=2,rb_swap=true})
    -- sh8601z_init({port = lcd.HWID_0, pin_dc = -1, pin_pwr = -1, pin_rst = 36, w = 368, h = 448, interface_mode=lcd.QSPI_MODE,bus_speed=80000000, rb_swap = true})
    lcd.setupBuff(nil, false)
    lcd.autoFlush(false)
    lcd.user_done() --必须在初始化完成后，在正式显示之前
    while true do 
        lcd.clear()
        log.info("wiki", "https://wiki.luatos.com/api/lcd.html")
        log.info("lcd.drawLine", lcd.drawLine(20,20 + test_cnt * 10,150,20 + test_cnt * 10,0x001F))
        log.info("lcd.drawRectangle", lcd.drawRectangle(20,40 + test_cnt * 10,120,70 + test_cnt * 10,0xF800))
        log.info("lcd.drawCircle", lcd.drawCircle(50 + test_cnt * 10,50 + test_cnt * 10,20,0x0CE0))

        lcd.flush()
        test_cnt = test_cnt + 1
        if test_cnt > 10 then
            test_cnt = 0
        end
        sys.wait(3000)
    end
end)

-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!

