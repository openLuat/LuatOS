--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2026.03.17
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；
]]

local lcd_drv = {}

function lcd_drv.init()
    pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)
    -- 开启屏幕供电
    local result = lcd.init("st7796",
        {
            pin_pwr = 1,       -- 背光控制引脚GPIO端口号
            port = lcd.HWID_0, -- 驱动端口
            pin_rst = 36,      -- lcd复位引脚
            direction = 1,     -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°
            w = 480,           -- lcd 水平分辨率
            h = 320,           -- lcd 竖直分辨率
            xoffset = 0,       -- x偏移
            yoffset = 0,       -- y偏移
        })

    log.info("lcd.init", result)

    if result then
        -- 初始化AirUI
        local width, height = lcd.getSize()
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            return result
        end

        -- 加载字体
        airui.font_load({
            type = "hzfont",
            path = nil,
            size = 14,
            cache_size = 512,
            antialias = 2,
        })

        return result
    end

    return result
end

return lcd_drv
