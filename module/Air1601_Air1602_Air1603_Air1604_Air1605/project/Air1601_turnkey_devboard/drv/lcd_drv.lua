--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于exd_ek79001_rgb显示IC初始化扩展库(Air1601版本)
@version 1.0
@date    2026.03.16
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数；
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

-- 加载 EK73215+EK79001 显示IC初始化扩展库
local exd = require "exd_ek79001_rgb"

local pin_rst, pin_pwr = 15, 2

local function lcd_drv_init()
    -- 开启屏幕供电
    gpio.setup(pin_pwr, 1)
    sys.wait(100)

    -- 显示初始化（1024x600，本板时序覆盖默认值）
    local ok, info = exd.setup({
        pin_rst = pin_rst,
        hbp = 120,
        hspw = 40,
        hfp = 150,
        vbp = 23,
        vspw = 10,
        vfp = 12,
        bus_speed = 51 * 1000 * 1000,
    })

    log.info("lcd_drv", "exd.setup", ok)
    log.info("lcd_drv", "screen", info.w, info.h)

    if ok then
        -- 初始化AirUI
        local result = airui.init(info.w, info.h)
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
