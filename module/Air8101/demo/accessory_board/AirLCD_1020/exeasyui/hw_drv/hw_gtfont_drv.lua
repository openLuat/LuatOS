--[[
@module  hw_gtfont_drv
@summary GTFont矢量字体驱动模块，使用AirFONTS_1000配件板
@version 1.0
@date    2025.12.2
@author  江访
@usage
本文件为GTFont矢量字体、lcd和tp驱动模块，核心业务逻辑为：
1、使用gtfont核心库驱动AirFONTS_1000矢量字库配件板；
2、根据配置的字体、lcd和tp参数，初始化exEasyUI默认使用的字体、硬件显示和触摸；
3、提供高质量矢量字体显示能力；

本文件的对外接口有0个：
1、require加载后自动执行初始化；

@api ui.hw_init(config)
@summary 初始化exEasyUI硬件系统
@table config 硬件配置参数表，包含字体配置、LCD配置和触摸配置
@field font_config table 字体配置参数
@field lcd_config table LCD显示配置参数
@field tp_config table 触摸屏配置参数
@return nil

@usage

]]

-- 使用gtfont矢量字库初始化exEasyUI硬件
ui.hw_init({
    font_config = { type = "gtfont", spi = { id = 1, cs = 3 }, size = 32 },

    -- lcd_config参数填写可以参考合宙exlcd显示扩展库exlcd.init(param)接口说明：https://docs.openluat.com/osapi/ext/exlcd/#31-exlcdinitparam
    lcd_config = {
        lcd_model = "AirLCD_1020", -- LCD型号
    },

    -- tp_config参数填写可以参考合宙extp触摸扩展库以下三个接口说明：https://docs.openluat.com/osapi/ext/extp/#41-extpinitparam
    -- 按extp.init(param)接口说明填写tp_model、i2c_id、pin_rst、pin_int参数
    -- 按extp.set_publish_enabled(msg_type, enabled)接口说明和实际需求填写message_enabled{}列表内参数
    -- 按extp.set_swipe_threshold(threshold)接口说明填写swipe_threshold和long_press_threshold参数
    tp_config = {
        tp_model = "AirLCD_1020", -- 触摸芯片/设备型号
        -- @param message_enabled 消息类型 ("ALL", "RAW_DATA", "TOUCH_DOWN", "MOVE_X", "MOVE_Y", "SWIPE_LEFT", "SWIPE_RIGHT", "SWIPE_UP", "SWIPE_DOWN", "SINGLE_TAP", "LONG_PRESS")
        message_enabled = {
            TOUCH_DOWN = true,      -- 启用按下检测
            MOVE_X = true,          -- 启用横向滑动
            MOVE_Y = true,          -- 启用纵向滑动
            SWIPE_LEFT = true,      -- 启用左滑手势
            SWIPE_RIGHT = true,     -- 启用右滑手势
            SWIPE_UP = true,        -- 启用上滑手势
            SWIPE_DOWN = true,      -- 启用下滑手势
            SINGLE_TAP = true,      -- 启用点击手势
            LONG_PRESS = false      -- 禁用长按手势
        },
        swipe_threshold = 10,       -- 设置滑动阈值
        long_press_threshold = 2000 -- 设置长按阈值（毫秒）
    }
})