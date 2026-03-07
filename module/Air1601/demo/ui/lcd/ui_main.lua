--[[
@module  ui_main
@summary 硬件初始化模块，负责SPI、LCD和背光的初始化
@version 1.0
@date    2026.03.06
@author  陈媛媛
@usage
本模块在require时自动执行硬件初始化，所有演示模块需先require本模块。
]]

-- 初始化SPI接口
spi_lcd = spi.deviceSetup(1, 8, 0, 0, 8, 50 * 1000 * 1000, spi.MSB, 1, 1)

-- 按配置执行lcd初始化
local result = lcd.init("st7796", {
    port = "device",
    pin_rst = 3,       -- 复位引脚
    pin_pwr = 54,      -- 背光控制引脚GPIO的ID号
    pin_dc = 2,        -- lcd数据/命令选择引脚GPIO ID号
    direction = 0,     -- lcd屏幕方向
    w = 320,
    h = 480,
    xoffset = 0,
    yoffset = 0,
    sleepcmd = 0X10,
    wakecmd = 0X11
}, spi_lcd)

if result then
    log.info("ui_main", "LCD初始化成功")
    -- 显示设置
    lcd.setupBuff(nil, true)
    lcd.autoFlush(false)
    -- 设置默认颜色，黑底白字
    lcd.setColor(0x0000, 0xFFFF)
    -- 打开背光
    -- gpio.setup(54, 1)
    -- log.info("ui_main", "背光已打开")
else
    log.error("ui_main", "LCD初始化失败")
end

-- 返回一个表，包含初始化状态（可选）
return { lcd_ok = result }