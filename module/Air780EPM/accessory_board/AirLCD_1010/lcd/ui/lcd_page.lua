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
local back_button = { x1 = 10, y1 = 445, x2 = 50, y2 = 475 }

--[[
绘制LCD演示页面；

@api lcd_page.draw()
@summary 绘制LCD演示页面的所有图形和UI元素
@return nil
]]
function lcd_page.draw()
    lcd.clear()
    -- 显示标题，使用22号自定义字体
    lcd.setFontFile("/luadb/customer_font_22.bin")

    -- 设置默认颜色
    lcd.setColor(0xFFFF, 0x0000)

    -- 显示标题区域
    lcd.fill(0, 0, 320, 40, 0x001F) -- 蓝色标题栏
    lcd.drawStr(80, 30, "LCD核心库演示", 0xFFFF)
    lcd.drawLine(20, 55, 300, 55, 0x8410)


    -- 显示演示内容,使用12号自定义字体
    -- === 第一区域：基本图形 ===
    lcd.setFontFile("/luadb/customer_font_12.bin")
    lcd.drawStr(20, 75, "基本图形绘制:", 0x0000)

    -- 绘制点
    lcd.drawStr(30, 98, "点:", 0x0000)
    lcd.drawPoint(55, 98, 0xFCC0)
    lcd.drawPoint(65, 98, 0x07E0)
    lcd.drawPoint(75, 98, 0x001F)

    -- 绘制线
    lcd.drawStr(30, 125, "线:", 0x0000)
    lcd.drawLine(55, 113, 115, 113, 0xFCC0)
    lcd.drawLine(55, 118, 115, 123, 0x07E0)
    lcd.drawLine(55, 123, 115, 118, 0x001F)

    -- 绘制矩形（预留右侧空间）
    lcd.drawStr(30, 160, "矩形:", 0x0000)
    lcd.drawRectangle(65, 138, 105, 163, 0x7296)
    lcd.fill(120, 138, 160, 163, 0x07E0)

    -- 绘制圆（预留右侧空间）
    lcd.drawStr(30, 200, "圆形:", 0x0000)
    lcd.drawCircle(90, 193, 15, 0x001F)
    lcd.drawCircle(130, 193, 15, 0xFCC0)

    lcd.drawLine(170, 70, 170, 300, 0x8410) -- 垂直分隔线

    -- === 第二区域：图片和二维码 ===
    lcd.drawStr(180, 75, "图片/二维码:", 0x0000)

    -- 图片显示区域 (80x80)
    lcd.drawStr(180, 100, "LOGO", 0x0000)
    lcd.drawRectangle(200, 110, 290, 200, 0x0000)
    lcd.showImage(205, 115, "/luadb/logo.jpg")

    -- 二维码区域 (80x80)
    lcd.drawStr(180, 215, "二维码", 0x0000)
    lcd.drawRectangle(200, 225, 290, 308, 0x0000)
    lcd.drawQrcode(205, 226, "https://docs.openluat.com/air780epm/", 80)

    lcd.drawLine(20, 325, 300, 325, 0x8410)

    -- === 第三区域：位图 ===
    lcd.drawLine(20, 235, 160, 235, 0x8410)

    -- 位图区域
    lcd.drawStr(20, 255, "位图示例:", 0x0000)

    -- 绘制位图
    local x_start = 30
    local y_start = 265
    lcd.drawXbm(x_start, y_start, 16, 16, string.char(
        0x00, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x3F, 0x80, 0x00,
        0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0x80, 0x00, 0xFE, 0x7F, 0x00, 0x00))

    lcd.drawXbm(x_start + 20, y_start, 16, 16, string.char(
        0x00, 0x00, 0x80, 0x00, 0xC4, 0x7F, 0x28, 0x00, 0x10, 0x00, 0xD0, 0x3F, 0x42, 0x20, 0x44, 0x22,
        0x40, 0x24, 0xF0, 0xFF, 0x24, 0x20, 0x24, 0x22, 0x24, 0x20, 0xE2, 0x7F, 0x02, 0x20, 0x02, 0x1E))

    lcd.drawXbm(x_start, y_start + 20, 16, 16, string.char(
        0x00, 0x00, 0x00, 0x01, 0x80, 0x01, 0x40, 0x02, 0x20, 0x04, 0x18, 0x18, 0xF4, 0x6F, 0x02, 0x00,
        0x00, 0x00, 0xF8, 0x1F, 0x08, 0x10, 0x08, 0x10, 0x08, 0x10, 0x08, 0x10, 0xF8, 0x1F, 0x08, 0x10))

    lcd.drawXbm(x_start + 20, y_start + 20, 16, 16, string.char(
        0x00, 0x00, 0x80, 0x00, 0x00, 0x01, 0xFE, 0x7F, 0x02, 0x40, 0x02, 0x40, 0x00, 0x01, 0xFC, 0x3F,
        0x04, 0x21, 0x04, 0x21, 0xFC, 0x3F, 0x04, 0x21, 0x04, 0x21, 0x04, 0x21, 0xFC, 0x3F, 0x04, 0x20))

    -- === 第四区域：字体 ===
    lcd.drawStr(20, 345, "字体示例:", 0x0000)

    -- 12号字体
    lcd.setFontFile("/luadb/customer_font_12.bin")
    lcd.drawStr(20, 368, "12px字体示例", 0x0000)

    -- 22号字体
    lcd.setFontFile("/luadb/customer_font_22.bin")
    lcd.drawStr(20, 398, "22px字体示例", 0x0000)

    -- 底部状态栏
    -- 绘制返回按钮
    lcd.setFontFile("/luadb/customer_font_12.bin")
    lcd.fill(0, 440, 320, 480, 0x001F) -- 蓝色背景
    lcd.fill(back_button.x1, back_button.y1, back_button.x2, back_button.y2, 0xC618)
    lcd.drawStr(20, 465, "返回", 0x0000)
    lcd.drawStr(180, 465, "触摸返回按钮回到主页", 0xFFFF)
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

--[[
页面进入时初始化；
@api lcd_page.on_enter()
@summary 页面进入时设置字体
@return nil
]]
function lcd_page.on_enter()
    -- 使用12号自定义字体
    lcd.setFontFile("/luadb/customer_font_12.bin")
end

--[[
页面离开时执行清理操作；
@api lcd_page.on_leave()
@summary 页面离开时恢复默认字体
@return nil
]]
function lcd_page.on_leave()
    -- 恢复使用12号自定义字体
    lcd.setFontFile("/luadb/customer_font_12.bin")
end

return lcd_page
