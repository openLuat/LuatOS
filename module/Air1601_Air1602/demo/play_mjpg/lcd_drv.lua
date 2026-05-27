--[[
@module  lcd_drv
@summary LCD驱动初始化模块
@version 1.0.0
@date    2026.05.19
@author  拓毅恒
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化 LCD屏幕；
2、配置LCD显示参数和显示缓冲区；
3、初始化AirUI;
4、支持多种屏幕方向和分辨率设置；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
]]

local function lcd_drv_init()
    -- 开启屏幕供电
    local result = lcd.init("custom", {
        -- 必需参数
        port = lcd.RGB,                    -- RGB接口
        w = 1024,                       -- 水平分辨率
        h = 600,                        -- 竖直分辨率
        -- 时序参数（可选，根据屏幕手册调整）
        hbp = 140,                      -- 水平后廊
        hspw = 20,                      -- 水平同步脉冲宽度
        hfp = 160,                      -- 水平前廊
        vbp = 20,                       -- 垂直后廊
        vspw = 3,                       -- 垂直同步脉冲宽度
        vfp = 12,                       -- 垂直前廊
        -- 总线速度（可选）
        bus_speed = 50 * 1000 * 1000,   -- 50MHz
    })

    log.info("lcd.init", result)

    if result then
        -- 开启缓冲区, 刷屏速度会加快, 但也消耗2倍屏幕分辨率的内存
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)

        -- 初始化AirUI
        local width, height = lcd.getSize()
        local airui_result = airui.init(width, height)
        if not airui_result then
            log.error("airui", "init failed")
            return false
        end
        log.info("airui", "init success", width, height)

        -- 开启背光引脚供电
        --gpio.setup(8, 1)

        return true
    end

    return false
end

-- 导出接口
lcd_drv = {
    init = lcd_drv_init
}
