--[[
@module  prod_lcd
@summary 产测项 LCD_TEST#：点亮屏幕并刷红/绿/蓝三竖条
@usage   LCD_TEST#
@return  string —— "OK" / "ERROR"
说明：缺色=某色数据线虚焊；花屏/坏线=时序或排线问题，需人工看屏确认。
]]

return function(arg)
    local lcd_drv = require "drv_lcd"

    if not lcd_drv.init() then
        log.error("prod_lcd", "lcd.init 失败，检查 LCD_EN/供电与排线")
        return "ERROR"
    end

    lcd_drv.color_bars()
    log.info("prod_lcd", "已刷红/绿/蓝三竖条，请人工确认无缺色/花屏")
    return "OK"
end
