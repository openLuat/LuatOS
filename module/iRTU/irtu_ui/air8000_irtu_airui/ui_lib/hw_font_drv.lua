--[[
@module  hw_font_drv
@summary 字体驱动配置模块
@version 1.0
@date    2025.11.28
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

local exlcd = require "exlcd"
local extp = require "extp"


local device = nil

-- 硬件配置参数
local hw_config = {
    -- lcd_config参数填写可以参考合宙exlcd显示扩展库exlcd.init(param)接口说明：https://docs.openluat.com/osapi/ext/exlcd/#31-exlcdinitparam
    lcd_config = {
        lcd_model = "AirLCD_1010",  -- LCD型号
        pin_vcc = 164,               -- 供电引脚
        pin_rst = 36,               -- 复位引脚
        pin_pwr = 25,                -- 背光控制引脚GPIO端口号
        pin_pwm = 2,                -- 背光控制引脚PWM端口号
        port = lcd.HWID_0,          -- 驱动端口
        pin_dc = 255,               -- lcd数据/命令选择引脚GPIO号，默认:nil
        direction = 0,              -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
        w = 320,                    -- lcd 水平分辨率
        h = 480,                    -- lcd 竖直分辨率
        xoffset = 0,                -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
        yoffset = 0,                -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
        sleepcmd = 0X10,            -- 睡眠命令，默认0X10
        wakecmd = 0X11,             -- 唤醒命令，默认0X11
        -- bus_speed = 50*1000*1000,   -- SPI总线速度,不填默认50M，若速率要求更高需要进行设置
        -- interface_mode = lcd.WIRE_4_BIT_8_INTERFACE_II,          -- lcd模式，默认lcd.WIRE_4_BIT_8_INTERFACE_I 
        -- direction0 = nil,
        -- direction90 = nil,
        -- direction180 = nil,
        -- direction270 = nil,
        -- hbp = nil,
        -- hspw = nil,
        -- hfp = 0,
        -- vbp = 0,
        -- vspw = 0,
        -- vfp = 0,
        -- initcmd = nil,
        -- flush_rate = nil,                   -- 刷新率
        spi_dev =  device,
        -- init_in_service = false,
    },

    -- tp_config参数填写可以参考合宙extp触摸扩展库以下三个接口说明：https://docs.openluat.com/osapi/ext/extp/#41-extpinitparam
    -- 按extp.init(param)接口说明填写tp_model、i2c_id、pin_rst、pin_int参数
    -- 按extp.set_publish_enabled(msg_type, enabled)接口说明和实际需求填写message_enabled{}列表内参数
    -- 按extp.set_swipe_threshold(threshold)接口说明填写swipe_threshold和long_press_threshold参数
    tp_config = {
        tp_model = "gt911", -- 触摸芯片/设备型号
        i2c_id = 0,               -- I2C总线ID
        pin_rst = 20,           -- 触摸芯片复位引脚(非必须)
        pin_int = gpio.WAKEUP0,             -- 触摸芯片中断引脚
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

function hw_font_drv.init_lcd()
    sys.wait(500)
	-- 打开iic供电
	gpio.setup(141, 1, gpio.PULLUP)

    local lcd_ok = exlcd.init(hw_config.lcd_config)
    lcd.setupBuff(nil, true)
    log.info("exEasyUI", "framebuffer enabled")
    lcd.autoFlush(false)

    -- 初始化触摸IC
    -- 使用配置表中的参数初始化触摸
    local tp_config = hw_config.tp_config
    extp.init(tp_config)

end

function hw_font_drv.init_tp()
    -- 初始化触摸IC
    -- 使用配置表中的参数初始化触摸
    local tp_config = hw_config.tp_config
    local tp_device = extp.init(tp_config)
    if tp_device ~= nil then
        log.info("exEasyUI", "触摸IC初始化成功")
        return tp_device
    end
    log.error("exEasyUI", "触摸IC初始化失败")
    return false
end

return hw_font_drv
