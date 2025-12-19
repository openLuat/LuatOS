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

-- 使用Air780EHM/EHV/EGH V2020版本以上14号固件内置的hzfont合宙矢量字库初始化exEasyUI硬件
ui.hw_init({
    font_config = { type = "hzfont", size = 24, antialias = -1 }, -- 默认-1，表示自动抗锯齿

    -- lcd_config参数填写可以参考合宙exlcd显示扩展库exlcd.init(param)接口说明：https://docs.openluat.com/osapi/ext/exlcd/#31-exlcdinitparam
    lcd_config = {
        lcd_model = "AirLCD_1000", -- LCD型号
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
    }
})