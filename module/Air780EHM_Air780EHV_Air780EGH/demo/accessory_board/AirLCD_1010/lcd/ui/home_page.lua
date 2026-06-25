--[[
@module  home_page
@summary 主页模块，提供应用入口和导航功能（触摸版）
@version 1.2
@date    2026.06.24
@author  江访
@usage
本模块为主页面功能模块，主要功能包括：
1、绘制主页面UI界面，显示应用标题和功能介绍；
2、提供三个功能按钮：LCD演示、摄像头、自定义字体；
3、处理主页面的触摸事件，实现页面导航；

对外接口：
1、home_page.draw()：绘制主页界面
2、home_page.handle_touch()：处理主页触摸事件
]]

local home_page = {}

-- 按钮区域定义（竖排三等宽居中）
local buttons = {
    lcd_page          = { x1 = 60, y1 = 100, x2 = 260, y2 = 180 },
    camera_preview    = { x1 = 60, y1 = 200, x2 = 260, y2 = 280 },
    customer_font_page = { x1 = 60, y1 = 300, x2 = 260, y2 = 380 }
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
    lcd.drawStr(106, 30, title, 0x0000)

    -- 显示说明文字
    lcd.drawStr(46, 50, content1, 0x0000)

    -- 绘制LCD演示按钮（蓝色）
    lcd.fill(buttons.lcd_page.x1, buttons.lcd_page.y1,
        buttons.lcd_page.x2, buttons.lcd_page.y2, 0x001F)
    lcd.drawStr(130, 138, "lcd核心库演示", 0xFFFF)

    -- 绘制摄像头按钮（橙色）
    lcd.fill(buttons.camera_preview.x1, buttons.camera_preview.y1,
        buttons.camera_preview.x2, buttons.camera_preview.y2, 0xFCC0)
    lcd.drawStr(120, 238, "摄像头:点击拍照", 0xFFFF)

    -- 绘制自定义字体演示按钮（绿色）
    lcd.fill(buttons.customer_font_page.x1, buttons.customer_font_page.y1,
        buttons.customer_font_page.x2, buttons.customer_font_page.y2, 0x07E0)
    lcd.drawStr(125, 338, "自定义字体", 0xFFFF)
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

    -- 检查摄像头按钮
    if x >= buttons.camera_preview.x1 and x <= buttons.camera_preview.x2 and
        y >= buttons.camera_preview.y1 and y <= buttons.camera_preview.y2 then
        switch_page("camera_preview")
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
