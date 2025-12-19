--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2025.12.1
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化AirLCD_1020 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、支持多种屏幕方向和分辨率设置；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
]]


local lcd_drv = {}

--[[
初始化LCD显示驱动；

@api lcd_drv.init()
@summary 配置并初始化AirLCD_1020 LCD屏幕
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

function lcd_drv.init()
    local result = lcd.init("nv3052c",
        {
            pin_pwr = 8,              -- 背光控制引脚GPIO端口号
            port = lcd.RGB,           -- 驱动端口
            direction = 0,            -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 800,                  -- lcd 水平分辨率
            h = 480,                  -- lcd 竖直分辨率
            xoffset = 0,              -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,              -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
            bus_speed = 30 * 1000 * 1000, -- SPI总线速度,不填默认50M，若速率要求更高需要进行设置
            hbp = 8,                  -- 水平后廊
            hspw = 4,                 -- 水平同步脉冲宽度
            hfp = 8,                  -- 水平前廊
            vbp = 16,                 -- 垂直后廊
            vspw = 4,                 -- 垂直同步脉冲宽度
            vfp = 16,                 -- 垂直前廊
        })

    log.info("lcd.init", result)

    if result then
        -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)

        -- 开启背光引脚供电
        gpio.setup(8,1)
    end
    return result
end

return lcd_drv
