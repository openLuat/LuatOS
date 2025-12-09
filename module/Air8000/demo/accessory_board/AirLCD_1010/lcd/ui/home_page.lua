--[[
@module  home_page
@summary 主页模块，提供应用入口和导航功能
@version 1.1
@date    2025.12.2
@author  江访
@usage
本模块为主页面功能模块，主要功能包括：
1、绘制主页面UI界面，显示应用标题和功能介绍；
2、提供三个功能按钮：LCD演示、矢量字体演示、自定义字体演示；
3、处理主页面的触摸事件，实现页面导航；

对外接口：
1、home_page.draw()：绘制主页界面
2、home_page.handle_touch()：处理主页触摸事件
]]

local home_page = {}

-- 屏幕尺寸
local width, height

local center_x

-- 按钮区域定义
local buttons = {
    lcd_page = { x1 = 10, y1 = 350, x2 = 100, y2 = 420 },
    gtfont_page = { x1 = 115, y1 = 350, x2 = 205, y2 = 420 },
    customer_font_page = { x1 = 220, y1 = 350, x2 = 310, y2 = 420 }
}

local title = "合宙lcd演示系统"
local content1 = "本页面使用的是系统内置的12号中文点阵字体"


--[[
绘制主页界面；

@api home_page.draw()
@summary 绘制主页面所有UI元素
@return nil
]]
function home_page.draw()
    lcd.clear()
    lcd.setColor(0xFFFF, 0x0000)
    lcd.setFont(lcd.font_opposansm12_chinese)

    -- 显示标题
    -- 后续V2020版本以上支持lcd核心库的固件会新增lcd.getStrWidth(title)接口获取文本宽度，对齐、居中、换行可使用
    -- width, height = lcd.getSize()
    -- center_x = width / 2
    -- lcd.drawStr(center_x - lcd.getStrWidth(title) / 2, 50, title, 0x0000) -- 自动居中
    lcd.drawStr(106, 50, title, 0x0000)

    -- 显示说明文字
    lcd.drawStr(46, 68, content1, 0x0000)

    -- 绘制LCD演示按钮
    lcd.fill(buttons.lcd_page.x1, buttons.lcd_page.y1,
        buttons.lcd_page.x2, buttons.lcd_page.y2, 0x001F)
    lcd.drawStr(15, 390, "lcd核心库演示", 0xFFFF)

    -- 绘制GTFont演示按钮
    lcd.fill(buttons.gtfont_page.x1, buttons.gtfont_page.y1,
        buttons.gtfont_page.x2, buttons.gtfont_page.y2, 0xF800)
    lcd.drawStr(148, 380, "外部", 0xFFFF)
    lcd.drawStr(124, 400, "矢量字体芯片", 0xFFFF)

    -- 绘制自定义字体演示按钮
    lcd.fill(buttons.customer_font_page.x1, buttons.customer_font_page.y1,
        buttons.customer_font_page.x2, buttons.customer_font_page.y2, 0x07E0)
    lcd.drawStr(235, 390, "自定义字体", 0xFFFF)
end

--[[
处理主页触摸事件；

@api home_page.handle_touch(x, y, switch_page)
@number x 触摸点X坐标，范围0-319
@number y 触摸点Y坐标，范围0-479
@function switch_page 页面切换回调函数
@return boolean 事件处理成功返回true，否则返回false
]]
function home_page.handle_touch(x, y, switch_page)
    -- 检查LCD演示按钮
    if x >= buttons.lcd_page.x1 and x <= buttons.lcd_page.x2 and
        y >= buttons.lcd_page.y1 and y <= buttons.lcd_page.y2 then
        switch_page("lcd")
        return true
    end

    -- 检查GTFont演示按钮
    if x >= buttons.gtfont_page.x1 and x <= buttons.gtfont_page.x2 and
        y >= buttons.gtfont_page.y1 and y <= buttons.gtfont_page.y2 then
        switch_page("gtfont")
        return true
    end

    -- 检查自定义字体演示按钮
    if x >= buttons.customer_font_page.x1 and x <= buttons.customer_font_page.x2 and
        y >= buttons.customer_font_page.y1 and y <= buttons.customer_font_page.y2 then
        switch_page("customer_font_page")
        return true
    end

    return false
end

return home_page
