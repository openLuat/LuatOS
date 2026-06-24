--[[
@module  customer_font_page
@summary 自定义字体演示模块
@version 1.0
@date    2025.11.20
@author  江访
@usage
本模块为自定义字体演示功能模块，主要功能包括：
1、展示外部自定义字体文件的使用方法；
2、演示不同颜色的字体显示效果；
3、提供字体文件路径和使用接口说明；
4、支持页面离开时恢复系统默认字体；

对外接口：
1、customer_font_page.draw()：绘制自定义字体演示页面
2、customer_font_page.handle_touch()：处理自定义字体页面触摸事件
3、customer_font_page.on_leave()：页面离开时恢复系统字体
]]

local customer_font_page = {}

-- 按钮区域定义
local back_button = { x1 = 10, y1 = 10, x2 = 80, y2 = 50 }


--[[
绘制自定义字体演示页面；

@api customer_font_page.draw()
@summary 绘制自定义字体演示页面的所有UI元素和字体内容
@return nil
]]
function customer_font_page.draw()
    lcd.clear()
    lcd.setFont(lcd.font_opposansm12_chinese)

    -- 绘制返回按钮
    lcd.fill(back_button.x1, back_button.y1, back_button.x2, back_button.y2, 0xC618)
    lcd.setColor(0x07E0, 0x0000)
    lcd.drawStr(35, 35, "返回", 0x0000)

    -- 设置默认颜色
    lcd.setColor(0xFFFF, 0x0000)

    -- 显示标题（使用系统字体）
    lcd.drawStr(106, 20 + 12, "自定义点阵字体演示", 0x0000)

    -- 设置自定义字体文件
    lcd.setFontFile("/luadb/customer_font_24.bin")

    lcd.drawStr(112, 206, "上海合宙", 0xF800) -- 红色
    lcd.drawStr(120, 240, "LuatOS", 0x07E0) -- 绿色
    lcd.drawStr(100, 274, "演示demo", 0x001F) -- 蓝色

    -- 恢复系统字体显示说明
    lcd.setFont(lcd.font_opposansm12_chinese)
    lcd.setColor(0xFFFF, 0x0000)

    -- 显示说明信息
    lcd.drawStr(20, 410, "- 字体路径: /luadb/customer_font_24.bin", 0x0000)
    -- 显示使用说明
    lcd.drawStr(20, 430, "使用接口:", 0x0000)
    lcd.drawStr(20, 450, "lcd.setFontFile(字体路径)", 0x0000)
    lcd.drawStr(20, 470, "lcd.drawStr(x, y,文本)", 0x0000)
end

--[[
处理自定义字体页面触摸事件；

@api customer_font_page.handle_touch(x, y, switch_page)
@number x 触摸点X坐标，范围0-319
@number y 触摸点Y坐标，范围0-479
@function switch_page 页面切换回调函数
@return boolean 事件处理成功返回true，否则返回false
]]
function customer_font_page.handle_touch(x, y, switch_page)
    -- 检查返回按钮
    if x >= back_button.x1 and x <= back_button.x2 and
        y >= back_button.y1 and y <= back_button.y2 then
        switch_page("home")
        return true
    end

    return false
end

--[[
页面离开时恢复系统字体；

@api customer_font_page.on_leave()
@summary 恢复系统默认字体设置
@return nil
]]
function customer_font_page.on_leave()
    -- 恢复使用12号中文字体
    lcd.setFont(lcd.font_opposansm12_chinese)
end

return customer_font_page
