--[[
@module  hw_font_drv
@summary 字体驱动配置模块
@version 1.0
@date    2025.12.9
@author  江访
@usage
本文件为字体驱动配置模块，核心业务逻辑为：
1、提供统一的硬件初始化接口；
2、支持默认字体、HzFont矢量字体和GTFont矢量字体配置；
3、配置LCD显示和触摸屏参数；

本文件的对外接口有1个：
1、hw_font_drv.init(font_config) - 初始化硬件系统；

@api hw_font_drv.init(font_config)
@summary 初始化exEasyUI硬件系统
@table font_config 字体配置参数（可选）
@field type string 字体类型，支持 "hzfont"、"gtfont"，不传则使用默认字体
@field size number 字体大小
@field antialias number 抗锯齿设置（仅HzFont有效）
@field spi table SPI配置（仅GTFont有效）
@return nil

@usage
-- 使用默认字体初始化硬件
hw_font_drv.init()

-- 使用HzFont矢量字体初始化硬件
hw_font_drv.init({
    type = "hzfont",
    size = 24,
    antialias = -1
})

-- 使用GTFont矢量字体初始化硬件
hw_font_drv.init({
    type = "gtfont",
    spi = { id = 0, cs = 8 },
    size = 32
})
]]

local hw_font_drv = {}

-- 硬件配置参数
local hw_config = {
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
}

function hw_font_drv.init(font_config)
    -- 如果有字体配置，则添加到硬件配置中
    if font_config then
        hw_config.font_config = font_config
    end

    -- 初始化硬件
    ui.hw_init(hw_config)

    log.info("hw_font_drv", "硬件初始化完成", font_config and "使用字体配置" or "使用默认字体")
end

return hw_font_drv
