--[[
@module  hw_font_drv
@summary 字体驱动配置模块
@version 1.0
@date    2025.11.28
@author  江访
@usage
本文件为字体驱动配置模块，核心业务逻辑为：
1、配置LCD显示和触摸屏参数；
2、提供统一的硬件初始化接口；

本文件的对外接口有1个：
1、ui.hw_init(hw_config) - 初始化硬件系统；

@api ui.hw_init(hw_config)
@summary 初始化exEasyUI硬件系统

@return nil

@usage

]]
local hw_font_drv = {}

-- 硬件配置参数
local hw_config = {
    -- lcd_config参数填写可以参考合宙exlcd显示扩展库exlcd.init(param)接口说明：https://docs.openluat.com/osapi/ext/exlcd/#31-exlcdinitparam
    lcd_config = {
        lcd_model = "AirLCD_1010", -- LCD型号
        -- pin_vcc = 24,           -- 供电引脚，使用GPIO控制屏幕供电可配置
        pin_rst = 36,              -- 复位引脚
        pin_pwr = 1,               -- 背光控制引脚GPIO ID号
        pin_pwm = 0,               -- 背光控制引脚PWM ID号
        port = lcd.HWID_0,         -- 驱动端口
        -- pin_dc = 0xFF,          -- lcd数据/命令选择引脚GPIO ID号，使用lcd 专用 SPI 接口 lcd.HWID_0不需要填此参数，使用通用SPI接口需要赋值
        direction = 0,             -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
        w = 320,                   -- lcd 水平分辨率
        h = 480,                   -- lcd 竖直分辨率
        xoffset = 0,               -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
        yoffset = 0,               -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
        sleepcmd = 0X10,           -- 睡眠命令，默认0X10
        wakecmd = 0X11,            -- 唤醒命令，默认0X11
        -- bus_speed = 50*1000*1000,                            -- SPI总线速度,不填默认50M，若速率要求更高需要进行设置
        -- interface_mode = lcd.WIRE_4_BIT_8_INTERFACE_I,       -- lcd模式，默认lcd.WIRE_4_BIT_8_INTERFACE_I
        -- direction0 = {0x36,0x00},                            -- 0°方向的命令，(不同屏幕ic会有差异)
        -- direction90 = {0x36,0x60},                           -- 90°方向的命令，(不同屏幕ic会有差异)
        -- direction180 ={0x36,0xc0} ,                          -- 180°方向的命令，(不同屏幕ic会有差异)
        -- direction270 = {0x36,0xA0},                          -- 270°方向的命令，(不同屏幕ic会有差异)
        -- hbp = nil,                                           -- 水平后廊
        -- hspw = nil,                                          -- 水平同步脉冲宽度
        -- hfp = 0,                                             -- 水平前廊
        -- vbp = 0,                                             -- 垂直后廊
        -- vspw = 0,                                            -- 垂直同步脉冲宽度
        -- vfp = 0,                                             -- 垂直前廊
        -- initcmd = nil,                                       -- 自定义屏幕初始化命令表
        -- flush_rate = nil,                                    -- 刷新率
        -- spi_dev = nil,                                       -- spi设备,当port = "device"时有效，当port ≠ "device"时可不填或者填nil
        -- init_in_service = false,                             -- 允许初始化在lcd service里运行，在后台初始化LCD，默认是false，Air8000/G/W/T/A、Air780EHM/EGH/EHV 支持填true，可加快初始化速度,默认SPI总线速度80M
    },

    -- tp_config参数填写可以参考合宙extp触摸扩展库以下三个接口说明：https://docs.openluat.com/osapi/ext/extp/#41-extpinitparam
    -- 按extp.init(param)接口说明填写tp_model、i2c_id、pin_rst、pin_int参数
    -- 按extp.set_publish_enabled(msg_type, enabled)接口说明和实际需求填写message_enabled{}列表内参数
    -- 按extp.set_swipe_threshold(threshold)接口说明填写swipe_threshold和long_press_threshold参数
    tp_config = {
        tp_model = "AirLCD_1010", -- 触摸芯片/设备型号
        i2c_id = 1,               -- I2C总线ID
        pin_rst = 0xFF,           -- 触摸芯片复位引脚(AirLCD_1010上没有引出该引脚)
        pin_int = 22,             -- 触摸芯片中断引脚
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
