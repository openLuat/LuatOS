--[[
@module  hzfont_demo
@summary HZFont矢量字体演示模块
@version 1.0
@date    2026.03.06
@author  陈媛媛
@usage
本模块演示HZFont内置矢量字库的使用，需在main.lua中require以启动。
]]

-- 初始化HZFont字库
hzfont.init()

-- 主显示循环
sys.taskInit(function()
    while true do
        lcd.clear(0x0000)

        lcd.drawHzfontUtf8(20, 30, "合宙LuatOS字体演示", 20, 0xF800, 1)
        lcd.drawHzfontUtf8(20, 60, "合宙LuatOS字体演示", 30, 0x07E0, 1)
        lcd.drawHzfontUtf8(20, 110, "hzfont字体演示", 40, 0x001F, 1)
        lcd.drawHzfontUtf8(20, 170, "hzfont演示", 50, 0xFD20, 1)

        lcd.drawHzfontUtf8(20, 250, "项目: " .. PROJECT, 24, 0xFFFF, 1)
        lcd.drawHzfontUtf8(20, 290, "版本: " .. VERSION, 24, 0xFFFF, 1)
        lcd.drawHzfontUtf8(20, 330, "分辨率: 320x480", 20, 0xFFE0, 1)
        lcd.drawHzfontUtf8(20, 360, "驱动: ST7796", 20, 0xFFE0, 1)

        -- 获取RTC时间并显示
        local t = rtc.get()
        if t then
            local time_str = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
            lcd.drawHzfontUtf8(20, 400, "时间: " .. time_str, 22, 0xFFFF, 1)
        else
            lcd.drawHzfontUtf8(20, 400, "时间: 未设置", 22, 0xFFFF, 1)
        end

        lcd.flush()
        sys.wait(2000)
    end
end)