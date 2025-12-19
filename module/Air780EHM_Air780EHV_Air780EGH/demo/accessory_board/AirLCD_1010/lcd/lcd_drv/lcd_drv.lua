--[[
@module  lcd_drv
@summary LCD显示驱动模块，基于lcd核心库
@version 1.0
@date    2025.11.20
@author  江访
@usage
本模块为LCD显示驱动功能模块，主要功能包括：
1、初始化ST7796 LCD控制器；
2、配置LCD显示参数和显示缓冲区；
3、支持多种屏幕方向和分辨率设置；

对外接口：
1、lcd_drv.init()：初始化LCD显示驱动
]]


local lcd_drv = {}

--[[
初始化LCD显示驱动；

@api lcd_drv.init()
@summary 配置并初始化ST7796 LCD控制器
@return boolean 初始化成功返回true，失败返回false

@usage
-- 初始化LCD显示
local result = lcd_drv.init()
if result then
    log.info("LCD初始化成功")
else
    log.error("LCD初始化失败")
end
]]

function lcd_drv.init()
    local result = lcd.init("st7796",
        {
            pin_rst = 36,                          -- 复位引脚
            pin_pwr = 1,                           -- 背光控制引脚GPIO的ID号
            port = lcd.HWID_0,                     -- 驱动端口
            -- pin_dc = 0xFF,                      -- lcd数据/命令选择引脚GPIO ID号，使用lcd 专用 SPI 接口 lcd.HWID_0不需要填此参数，使用通用SPI接口需要赋值
            direction = 0,                         -- lcd屏幕方向 0:0° 1:90° 2:180° 3:270°，屏幕方向和分辨率保存一致
            w = 320,                               -- lcd 水平分辨率
            h = 480,                               -- lcd 竖直分辨率
            xoffset = 0,                           -- x偏移(不同屏幕ic 不同屏幕方向会有差异)
            yoffset = 0,                           -- y偏移(不同屏幕ic 不同屏幕方向会有差异)
            sleepcmd = 0X10,                       -- 睡眠命令，默认0X10
            wakecmd = 0X11,                        -- 唤醒命令，默认0X11
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
        })

    log.info("lcd.init", result)

    if result then
        -- 显示设置
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)
    end

    return result
end

return lcd_drv
