--[[
@module  lcd_page
@summary LCD图形绘制演示模块
@version 1.0
@date    2025.11.20
@author  江访
@usage
本模块为LCD图形绘制演示功能模块，主要功能包括：
1、展示LCD核心库的基本图形绘制功能；
2、演示点、线、矩形、圆形等基本图形绘制；
3、显示图片和二维码生成功能；
4、提供颜色示例展示；

对外接口：
1、lcd_page.draw()：绘制LCD演示页面
2、lcd_page.handle_touch()：处理LCD页面触摸事件
]]
local lcd_page = {}

-- 按钮区域定义
local back_button = {x1 = 10, y1 = 10, x2 = 80, y2 = 50}

--[[
绘制LCD演示页面；

@api lcd_page.draw()
@summary 绘制LCD演示页面的所有图形和UI元素
@return nil
]]
function lcd_page.draw()
    lcd.clear()
    lcd.setFont(lcd.font_opposansm12_chinese)
    
    -- 绘制返回按钮
    lcd.fill(back_button.x1, back_button.y1, back_button.x2, back_button.y2, 0xC618)
    lcd.setColor(0x07E0, 0x0000)
    lcd.drawStr(35, 35, "返回", 0x0000)
    
    -- 设置默认颜色
    lcd.setColor(0xFFFF, 0x0000)
    
    -- 显示标题
    lcd.drawStr(124, 20 + 12, "lcd核心库演示", 0x0000)
    
    -- 绘制各种图形
    lcd.drawStr(20, 60 + 12, "基本图形绘制:", 0x0000)
    
    -- 绘制点
    lcd.drawPoint(30, 100, 0xFCC0)
    lcd.drawPoint(40, 100, 0x07E0)
    lcd.drawPoint(50, 100, 0x001F)
    
    -- 绘制线
    lcd.drawLine(70, 90, 150, 90, 0xFCC0)
    lcd.drawLine(70, 100, 150, 110, 0x07E0)
    lcd.drawLine(70, 110, 150, 90, 0x001F)
    
    -- 绘制矩形
    lcd.drawRectangle(170, 90, 220, 120, 0x7296)
    lcd.fill(230, 90, 280, 120, 0x07E0)
    
    -- 绘制圆
    lcd.drawCircle(100, 180, 25, 0x001F)
    lcd.drawCircle(180, 180, 25, 0xFCC0)
    
    -- 显示图片示例文字
    lcd.drawStr(20, 220 + 12, "图片显示区域", 0x0000)
    lcd.drawRectangle(20, 240, 150, 370, 0x0000)
    lcd.showImage(45, 265, "/luadb/logo.jpg")
    
    -- 显示二维码示例文字
    lcd.drawStr(170, 220 + 12, "二维码区域", 0x0000)
    lcd.drawRectangle(170, 240, 300, 370, 0x0000)
    lcd.drawQrcode(185, 255, "https://docs.openluat.com/air8000/", 100)
    
    -- 显示颜色示例
    lcd.drawStr(20, 390 + 12, "颜色示例:", 0x0000)
    lcd.fill(100, 390, 120, 410, 0xF800)
    lcd.fill(130, 390, 150, 410, 0x07E0)
    lcd.fill(160, 390, 180, 410, 0x001F)
    lcd.fill(190, 390, 210, 410, 0xFCC0)
    lcd.fill(220, 390, 240, 410, 0x0000)
end

--[[
处理LCD页面触摸事件；

@api lcd_page.handle_touch(x, y, switch_page)
@number x 触摸点X坐标，范围0-319
@number y 触摸点Y坐标，范围0-479
@function switch_page 页面切换回调函数
@return boolean 事件处理成功返回true，否则返回false
]]
function lcd_page.handle_touch(x, y, switch_page)
    -- 检查返回按钮
    if x >= back_button.x1 and x <= back_button.x2 and
       y >= back_button.y1 and y <= back_button.y2 then
        switch_page("home")
        return true
    end
    return false
end

return lcd_page