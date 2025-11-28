--[[
@module  hw_gtfont_drv
@summary GTFont矢量字体驱动模块，使用AirFONTS_1000配件板
@version 1.0
@date    2025.11.25
@author  江访
@usage
本文件为GTFont矢量字体驱动功能模块，核心业务逻辑为：
1、使用gtfont核心库驱动AirFONTS_1000矢量字库配件板；
2、初始化exEasyUI硬件显示系统，配置SPI接口和字体大小参数；
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
-- 使用GTFont矢量字体初始化硬件
ui.hw_init({
    font_config = { type = "gtfont", spi = { id = 0, cs = 8 }, size = 32 },
    lcd_config = {
        lcd_model = "AirLCD_1010",
        pin_rst = 36,
        direction = 0,
        w = 320,
        h = 480
    },
    tp_config = {
        tp_model = "AirLCD_1010",
        i2c_id = 1,
        pin_int = 22
    }
})
]]

-- 使用gtfont矢量字库初始化exEasyUI硬件
ui.hw_init({
    font_config = { type = "gtfont", spi = { id = 0, cs = 8 }, size = 32 },

    -- lcd_config参数填写可以参考合宙exlcd显示扩展库exlcd.init(param)接口说明：https://docs.openluat.com/osapi/ext/exlcd/#31-exlcdinitparam
    lcd_config = {
        lcd_model = "AirLCD_1010", -- LCD型号
        -- pin_vcc = 24,                  -- 供电引脚，使用GPIO控制屏幕供电可配置
        pin_rst = 36,              -- 复位引脚
        pin_pwr = 1,               -- 背光控制引脚GPIO ID号
        pin_pwm = 0,               -- 背光控制引脚PWM D号
        port = lcd.HWID_0,         -- 驱动端口
        -- pin_dc = 0xFF,          -- lcd数据/命令选择引脚GPIO ID号，默认:nil
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
        pin_rst = 0xFF,           -- 触摸芯片复位引脚(非必须)
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
})