--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2025.12.1
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


local lcd_drv = {}

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

function lcd_drv.init()
    -- 开启屏幕供电
    gpio.setup(141, 1)
    local result = lcd.init("st7796",
        {
            pin_pwr = 1,       -- 背光控制引脚GPIO端口号
            port = lcd.HWID_0, -- 驱动端口
            pin_rst = 36,      -- lcd复位引脚
            direction = 0,     -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 320,           -- lcd 水平分辨率
            h = 480,           -- lcd 竖直分辨率
            xoffset = 0,       -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,       -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
        })

    log.info("lcd.init", result)

    if result then
        -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)

        -- 初始化AirUI
        local width, height = lcd.getSize()
        local result = airui.init(width, height)
        if not result then
            log.error("airui", "init failed")
            return result
        end

        -- 加载字体
        airui.font_load({
            type = "hzfont",    -- 字体类型，hzfont
            path = nil,         -- 字体路径，Air8000固件内置，无需填写
            size = 14,         -- 默认字体大写
            cache_size = 512,   -- 
            antialias = 4, -- 字体抗锯齿等级，1-4级，级别越高抗锯齿效果越好，加载时间越长
        })

        -- 开启背光引脚供电
        gpio.setup(1, 1)

        return result
    end

    return result
end

return lcd_drv
