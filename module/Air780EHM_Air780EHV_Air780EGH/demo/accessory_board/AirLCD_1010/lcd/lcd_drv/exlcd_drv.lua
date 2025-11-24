--[[
@module  exlcd_drv
@summary 扩展LCD显示驱动模块，基于exlcd扩展库
@version 1.0
@date    2025.11.20
@author  江访
@usage
本模块为扩展LCD显示驱动功能模块，主要功能包括：
1、初始化AirLCD_1010扩展LCD显示；
2、配置显示缓冲区和自动刷新设置；

对外接口：
1、exlcd_drv.init()：初始化扩展LCD显示驱动
如果需要实现背光亮度调节，参考exlcd扩展库中的exlcd.set_bl(level)进行设置
]]

local exlcd = require "exlcd"

local exlcd_drv = {}

--[[
初始化扩展LCD显示驱动；

@api exlcd_drv.init()
@summary 配置并初始化AirLCD_1010扩展LCD显示
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化扩展LCD显示
local result = exlcd_drv.init({})
if result then
    log.info("扩展LCD初始化成功")
else
    log.error("扩展LCD初始化失败")
end
]]

function exlcd_drv.init()
    local result = exlcd.init({lcd_model = "AirLCD_1010", pin_vcc = 0xFF})

    log.info("exlcd.init", result)

    if result then
        -- 显示设置
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)
    end

    return result
end

return exlcd_drv