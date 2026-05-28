--[[
@module  exlcd_drv
@summary 扩展LCD显示驱动模块，基于exlcd扩展库
@version 1.0
@date    2025.12.3
@author  江访
@usage
本模块为扩展LCD显示驱动功能模块，主要功能包括：
1、初始化AirLCD_1010扩展LCD显示；
2、配置显示缓冲区和自动刷新设置；

对外接口：
加载exlcd_drv模块后，自动进行LCD显示驱动初始化，无需调用其他函数：
]]

local exlcd = require "exlcd"


local function exlcd_drv_init()
    local result = exlcd.init({lcd_model = "AirLCD_1010"})

    log.info("exlcd.init", result)

    if result then
        -- 显示设置
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)
    end
end

exlcd_drv_init()