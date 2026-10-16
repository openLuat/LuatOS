--[[
@module  lcd_drv
@summary LCD驱动初始化模块
@version 1.0.0
@date    2026.05.19
@author  拓毅恒
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
2、lcd_drv.get_size()：查询屏幕尺寸
]]

-- 加载 EK73215+EK79001 显示IC初始化扩展库
local exd = require "exd_ek79001_rgb"

local lcd_width, lcd_height = 1024, 600

local function lcd_drv_init()
    -- 显示初始化（1024x600，时序用扩展库默认值）
    local ok, info = exd.setup({
        pin_rst = 22,
        screen_size = 5.0,
    })

    log.info("lcd_drv", "exd.setup", ok)

    if ok then
        lcd_width, lcd_height = info.w, info.h

        -- 初始化AirUI
        local airui_result = airui.init(info.w, info.h)
        if not airui_result then
            log.error("airui", "init failed")
            return false
        end
        log.info("airui", "init success", info.w, info.h)

        -- 开启背光引脚供电
        --gpio.setup(8, 1)

        return true
    end

    return false
end

-- 查询屏幕尺寸
local function lcd_drv_get_size()
    return lcd_width, lcd_height
end

-- 导出接口
lcd_drv = {
    init = lcd_drv_init,
    get_size = lcd_drv_get_size,
}
