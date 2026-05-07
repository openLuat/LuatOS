--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库(Air1601版本)
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
]]




--[[
初始化LCD显示驱动；

@api lcd_drv.init()
@summary 配置并初始化LCD屏幕
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化LCD显示
local result = lcd_drv.init()
if result then
    log.info("LCD初始化成功")
else
    log.error("LCD初始化失败")
end
]]

local port, pin_reset, bl = lcd.RGB, 0, 2

local function lcd_drv_init()
    -- 开启屏幕供电
    local result = lcd.init("custom", {
        port = port,
        hbp = 120,
        hspw = 40,
        hfp = 150,
        vbp = 23,
        vspw = 10,
        vfp = 12,
        bus_speed = 51 * 1000 * 1000,
        pin_pwr = bl,
        pin_rst = pin_reset,
        direction = 0,
        w = 1024,
        h = 600
    })

    log.info("lcd.init", result)
    log.info("lcd.getSize", lcd.getSize())

    if result then
        -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)

        -- 初始化AirUI
        local width, height = lcd.getSize()
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            -- return result
        end

        -- 加载字体
        airui.font_load({
            type = "hzfont",
            path = nil,
            size = 14,
            cache_size = 512,
            antialias = 1,
        })

        local version_result = airui.version()
        log.info("airui", "version -> " .. version_result)

        -- return result
    end

end

-- lcd_drv_init()
sys.taskInit(lcd_drv_init)