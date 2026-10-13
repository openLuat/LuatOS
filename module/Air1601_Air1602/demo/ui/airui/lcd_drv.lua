--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于exd_hx8282_rgb显示IC初始化扩展库
@version 1.0
@date    2025.12.1
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

-- 加载 HX8282 显示IC初始化扩展库
local exd = require "exd_hx8282_rgb"

local pin_rst, pin_pwr = 22, 23

-- 获取屏幕尺寸：固件支持display核心库用display接口，不支持用lcd接口，都取不到时用扩展库配置值
local function get_screen_size(fallback_w, fallback_h)
    local width, height = 0, 0
    -- 固件支持display核心库用display接口获取
    if rawget(_G, "display") and display.getSize then
        width, height = display.getSize()
    end
    -- display接口取不到时用lcd接口获取
    if (width == 0 or height == 0) and rawget(_G, "lcd") and lcd.getSize then
        width, height = lcd.getSize()
    end
    -- 两个接口都取不到时用扩展库配置的分辨率
    if width == 0 or height == 0 then
        width, height = fallback_w, fallback_h
    end
    return width, height
end

local function lcd_drv_init()
    -- 开启屏幕供电
    gpio.setup(pin_pwr, 1)
    sys.wait(100)

    -- 显示初始化（5寸 1024x600，时序用扩展库默认值）
    local ok, info = exd.setup({
        pin_rst = pin_rst,
        screen_size = 5.0,
    })

    log.info("lcd_drv", "exd.setup", ok)

    if ok then
        -- 初始化AirUI
        local width, height = get_screen_size(info.w, info.h)
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            return result
        end

        -- 开启背光引脚供电
        --gpio.setup(8, 1)

        return result
    end

end

lcd_drv_init()
