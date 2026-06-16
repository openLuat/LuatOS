--[[
@module  lcd_drv
@summary LCD驱动初始化模块
@version 1.0.0
@date    2026.05.19
@author  拓毅恒
@usage
本模块负责LCD显示屏的初始化和AirUI框架初始化：
1. 初始化 ST7796 LCD 驱动
2. 配置 320x480 分辨率
3. 初始化 AirUI 框架

使用方式：
1. 在 main.lua 中 require "lcd_drv"
2. 调用 lcd_drv_init() 初始化LCD

注意事项：
1. 背光在初始化完成后再开启，避免白屏
2. GPIO36 控制LCD复位
3. GPIO1 控制背光
]]

-- ====================== LCD驱动初始化 ======================

-- LCD初始化函数
function lcd_drv_init()
    local result = lcd.init("st7796",
        {
            pin_rst = 36,                           -- 复位引脚
            pin_pwr = nil,                          -- 背光控制引脚，先不开启
            port = lcd.HWID_0,                      -- 驱动端口
            direction = 0,                          -- lcd屏幕方向
            w = 320,                                -- lcd 水平分辨率
            h = 480,                                -- lcd 竖直分辨率
            xoffset = 0,
            yoffset = 0,
            sleepcmd = 0X10,
            wakecmd = 0X11,
        })

    log.info("lcd.init", result)

    if result then

        -- 初始化AirUI
        local width, height = lcd.getSize()
        local airui_result = airui.init(width, height)
        if not airui_result then
            log.error("airui", "init failed")
            return false
        end
        log.info("airui", "init success", width, height)
    end

    return result
end
