--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于exd_ek79001_rgb显示IC初始化扩展库
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

-- 加载 EK73215+EK79001 显示IC初始化扩展库
local exd = require "exd_ek79001_rgb"

local pin_rst, pin_pwr = 15, 2

local function lcd_drv_init()
    -- 开启屏幕供电
    gpio.setup(pin_pwr, 1)
    sys.wait(100)

    -- 显示初始化（1024x600，时序用扩展库默认值，PCLK 高有效）
    local ok, info = exd.setup({
        pin_rst = pin_rst,
        clk_polarity = 1,
    })

    log.info("lcd_drv", "exd.setup", ok)

    if ok then
        -- 初始化AirUI
        local width, height = info.w, info.h
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            return result
        end

        -- 加载中文字体

        -- Air8101使用104号固件将字体文件烧录到文件系统，从文件系统中加载hzfont字库，从而支持12-255号中文显示
        airui.font_load({
            type = "hzfont",       -- 字体类型，可选 "hzfont" 或 "bin"
            path = nil,            -- 字体路径，对于 "hzfont"，传 nil 则使用内置字库
            size = 20,             -- 字体大小，默认 16
            cache_size = 1024,     -- 缓存字数大小，默认 2048
            antialias = 1,         -- 抗锯齿等级1-3，默认 1
            -- load_to_psram= true,
            global = true
        })

        -- 查询当前固件内AirUI核心库版本，V1.0.3新增接口
        log.info("airui", "version -> " .. airui.version())

        return result
    end
end

lcd_drv_init()
