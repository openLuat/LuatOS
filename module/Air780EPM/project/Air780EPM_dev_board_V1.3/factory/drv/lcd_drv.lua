--[[
@module  lcd_drv
@summary LCD 显示驱动（ST7796，320×480 竖屏）
@version 1.0
@date    2026.10.16
@usage
初始化 AirLCD_1000 显示 IC ST7796，竖屏 320×480。
通过 HARDWARE_ENV 全局变量适配硬件环境（本工程固定 DEV_BOARD_V1.3）。

对外接口：
  lcd_drv.init() —— require 即执行，完成 lcd.init + setupBuff + autoFlush(false)
]]

--[[
HARDWARE_ENV 参数说明：
  "CORE_BOARD":     核心板直连，不需要 GPIO 供电，背光 GPIO1 控制
  "DEV_BOARD_V1.2": V1.2 开发板，GPIO28 控制 LCD 电源，无背光控制
  "DEV_BOARD_V1.3": V1.3 开发板，GPIO29 控制 LCD 电源，GPIO30 控制背光
]]

local function lcd_drv_init()
    local pin_pwr = nil  -- 默认不通过 lcd 库控制背光

    if HARDWARE_ENV == "DEV_BOARD_V1.2" then
        gpio.setup(28, 1) -- GPIO28 打开 LCD 电源供电，无需控制背光
    elseif HARDWARE_ENV == "DEV_BOARD_V1.3" then
        gpio.setup(29, 1) -- GPIO29 打开 LCD 电源供电
        gpio.set(29, 1)
        gpio.setup(30, 0) -- GPIO30 拉低开启背光（拉高灭屏，拉低亮屏）
        gpio.set(30, 0)
    else
        pin_pwr = 1       -- 核心板使用 GPIO1 控制背光
    end

    local result = lcd.init("st7796",
        {
            pin_rst = 36,           -- 复位引脚
            pin_pwr = pin_pwr,      -- 背光控制引脚（V1.2 为 nil）
            port = lcd.HWID_0,      -- lcd 专用 SPI 接口
            direction = 0,          -- 0°（竖屏）
            w = 320,                -- 水平分辨率
            h = 480,                -- 竖直分辨率
            xoffset = 0,
            yoffset = 0,
            sleepcmd = 0X10,
            wakecmd = 0X11,
        })

    log.info("lcd.init", result)

    if result then
        lcd.setupBuff(nil, true)
        lcd.autoFlush(false)
    end
end

lcd_drv_init()
