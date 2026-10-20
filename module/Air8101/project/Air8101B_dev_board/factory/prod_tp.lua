--[[
@module  prod_tp
@summary 产测项 TP_TEST#：触屏点测（15 秒），触点画方块
@usage   TP_TEST#
@return  string —— "OK" / "ERROR"
说明
1. 期限内至少 1 次有效触摸即通过，触摸次数与坐标写日志；
2. 判据是"能读到坐标"，不判位置准不准（校准属业务模式）。
]]

local TIMEOUT_S = 15

return function(arg)
    local lcd_drv = require "drv_lcd"
    local tp_drv  = require "drv_tp"

    if not lcd_drv.init() then
        log.error("prod_tp", "lcd.init 失败")
        return "ERROR"
    end
    if not tp_drv.init() then
        log.error("prod_tp", "tp.init 失败，检查 I2C1 与 TP_RST/INT")
        return "ERROR"
    end

    lcd_drv.solid(lcd_drv.COLOR.BLACK)
    log.info("prod_tp", "请点屏幕，", TIMEOUT_S, "秒内至少点一次")

    local count, lx, ly = 0, 0, 0
    local t0 = os.time()
    while os.time() - t0 < TIMEOUT_S do
        local got, event, x, y = sys.waitUntil("TP_RAW", 1000)
        if got and event == tp.EVENT_DOWN then
            count = count + 1
            lx, ly = x, y
            lcd_drv.mark(x, y, lcd_drv.COLOR.GREEN)
        end
    end

    log.info("prod_tp", "触摸次数:", count, "最后坐标:", lx, ly)
    if count == 0 then
        log.error("prod_tp", TIMEOUT_S .. " 秒内未检测到触摸")
        return "ERROR"
    end
    return "OK"
end
