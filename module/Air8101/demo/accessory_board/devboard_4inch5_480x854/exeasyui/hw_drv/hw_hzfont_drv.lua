--[[
@module  hw_hzfont_drv
@summary HZFont矢量字体驱动模块，使用合宙内置矢量字库
@version 1.0
@date    2025.12.3
@author  江访
@usage
本文件为HZFont矢量字体、lcd和tp驱动模块，核心业务逻辑为：
1、使用Air780EHM/EHV/EGH V2020版本以上14号固件或114号固件内置的hzfont合宙矢量字库；
2、根据配置的字体、lcd和tp参数，初始化exEasyUI默认使用的字体、硬件显示和触摸；
3、提供动态字体大小调整和高质量字体显示能力；

本文件无对外接口，require加载后自动执行初始化；

@api ui.hw_init(config)
@summary 初始化exEasyUI硬件系统
@table config 硬件配置参数表，包含字体配置、LCD配置和触摸配置
@field font_config table 字体配置参数
@field lcd_config table LCD显示配置参数
@field tp_config table 触摸屏配置参数
@return nil

@usage

]]

-- 使用Air780EHM/EHV/EGH V2020版本以上14号固件内置的hzfont合宙矢量字库初始化exEasyUI硬件
ui.hw_init({
    font_config = { type = "hzfont", path = "/MiSans_gb2312.ttf", size = 24, to_psram = true, antialias = -1 },  -- 默认-1，表示自动抗锯齿

    -- lcd_config参数填写可以参考合宙exlcd显示扩展库exlcd.init(param)接口说明：https://docs.openluat.com/osapi/ext/exlcd/#31-exlcdinitparam
    lcd_config = {
        lcd_model = "st7701sn", -- LCD型号
        pin_rst = 36,           -- 复位引脚
        pin_pwr = 7,            -- 背光控制引脚GPIO端口号
        port = lcd.RGB,         -- 驱动端口
        direction = 0,          -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
        w = 480,                -- lcd 水平分辨率
        h = 854,                -- lcd 竖直分辨率
        xoffset = 0,            -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
        yoffset = 0,            -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
    }
})
