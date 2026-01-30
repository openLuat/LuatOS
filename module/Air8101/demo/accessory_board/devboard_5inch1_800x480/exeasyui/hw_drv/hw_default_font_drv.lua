--[[
@module  hw_default_font_drv
@summary 默认字体、lcd和tp驱动模块，使用内置12号点阵字体
@version 1.0
@date    2025.12.2
@author  江访
@usage
本文件为默认字体、lcd和tp驱动模块，核心业务逻辑为：
1、使用lcd内核固件中自带的12号中文字体；
2、根据配置的字体、lcd和tp参数，初始化exEasyUI默认使用的字体、硬件显示和触摸；
3、提供无需外部硬件的字体显示能力；

本文件无对外接口，require加载后自动执行初始化；

@api ui.hw_init(config)
@summary 初始化exEasyUI硬件系统
@table config 硬件配置参数表，包含LCD配置和触摸配置
@field lcd_config table LCD显示配置参数
@field tp_config table 触摸屏配置参数
@return nil

@usage

]]

-- 使用默认12号中文字体初始化exEasyUI硬件
ui.hw_init({
    -- lcd_config参数填写可以参考合宙exlcd显示扩展库exlcd.init(param)接口说明：https://docs.openluat.com/osapi/ext/exlcd/#31-exlcdinitparam
    lcd_config = {
        lcd_model = "h050iwv", -- LCD型号
        pin_rst = 36,          -- 复位引脚
        pin_pwr = 7,           -- 背光控制引脚GPIO端口号
        port = lcd.RGB,        -- 驱动端口
        direction = 0,         -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
        w = 800,               -- lcd 水平分辨率
        h = 480,               -- lcd 竖直分辨率
        xoffset = 0,           -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
        yoffset = 0,           -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
    },

    -- tp_config参数填写可以参考合宙extp触摸扩展库以下三个接口说明：https://docs.openluat.com/osapi/ext/extp/#41-extpinitparam
    -- 按extp.init(param)接口说明填写tp_model、i2c_id、pin_rst、pin_int参数
    -- 按extp.set_publish_enabled(msg_type, enabled)接口说明和实际需求填写message_enabled{}列表内参数
    -- 按extp.set_swipe_threshold(threshold)接口说明填写swipe_threshold和long_press_threshold参数
    tp_config = {
        tp_model = "gt9157",           -- 触摸芯片/设备型号
        i2c_id = i2c.createSoft(8, 5), -- SCL=8, SDA=5
        pin_int = 6,
        pin_rst = 9,
        w = 800,
        h = 480,
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
