--[[
@module  image_demo
@summary 图片显示演示模块
@version 1.0
@date    2026.03.06
@author  江访
@usage
本模块演示在LCD上显示JPG图片，需在main.lua中require以启动。
]]

log.info("image_demo", "项目:", PROJECT, VERSION)

sys.taskInit(function()
    sys.wait(100)  -- 等待硬件稳定

    -- 显示图片
    local image_path = "/luadb/picture.jpg"

    if io.exists(image_path) then
        log.info("image_drv", "找到图片文件:", image_path)
        lcd.clear(0x0000)
        lcd.showImage(0, 0, image_path)
        lcd.flush()
    else
        log.error("image_drv", "图片文件不存在:", image_path)
        lcd.clear(0x001F)  -- 蓝色背景
        lcd.setFont(lcd.font_opposansm16)
        lcd.setColor(0xFFFF, 0x001F)
        lcd.drawStr(20, 180, "图片文件不存在:")
        lcd.drawStr(40, 220, image_path)
        lcd.flush()
    end

    -- 保持运行
    while true do
        sys.wait(1000)
    end
end)