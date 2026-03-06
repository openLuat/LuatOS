--[[
@module  draw_drv
@summary 基本图形绘制演示模块
@version 1.0
@date    2026.03.06
@author  陈媛媛
@usage
本模块演示绘制点、线、矩形、圆和文字，需在main.lua中require以启动。
]]

log.info("draw_demo", "项目:", PROJECT, VERSION)

sys.taskInit(function()
    sys.wait(100)  -- 等待硬件稳定

    -- 1. 清屏为白色
    lcd.clear(0xFFFF)
    lcd.flush()
    sys.wait(100)

    -- 2. 绘制一条线
    lcd.drawLine(50, 50, 270, 50, 0x001F)  -- 蓝色线条

    -- 3. 绘制空心矩形
    lcd.drawRectangle(30, 100, 150, 180, 0xF800)  -- 红色边框

    -- 4. 绘制空心圆
    lcd.drawCircle(100, 350, 40, 0x001F)  -- 蓝色边框

    -- 5. 显示文字
    lcd.setFont(lcd.font_opposansm16)
    lcd.drawStr(60, 240, "hello, hezhou", 0x0000)

    lcd.flush()
    log.info("draw_drv", "图形绘制完成")

    -- 保持运行
    while true do
        sys.wait(1000)
    end
end)