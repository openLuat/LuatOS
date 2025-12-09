--[[
@module  home_page
@summary 主页模块，提供应用入口和导航功能
@version 1.0
@date    2025.12.8
@author  江访
@usage
本模块为主页模块，核心业务逻辑为：
1、提供应用入口和导航功能，支持LCD演示和自定义字体演示两个功能选项；
2、显示系统标题和操作提示信息；
3、处理主页面的触摸事件；

注意：使用自定义字体显示中文

本文件的对外接口有3个：
1、home_page.draw()：绘制主页面UI；
2、home_page.handle_touch()：处理触摸事件；
3、home_page.on_enter()：页面进入时重置状态；
]]

local home_page = {}

-- 按钮区域定义（调整为2个按钮）
local buttons = {
    { name = "lcd", text = "LCD演示", x1 = 40, y1 = 150, x2 = 140, y2 = 240, color = 0x001F }, -- 蓝色
    { name = "customer_font", text = "自定义字体", x1 = 180, y1 = 150, x2 = 280, y2 = 240, color = 0xF800 } -- 红色
}

--[[
绘制主页界面；
@api home_page.draw()
@summary 绘制主页面所有UI元素
@return nil
]]
function home_page.draw()
    lcd.clear()

    -- 显示标题，使用22号自定义字体
    lcd.setColor(0xFFFF, 0x0000)
    lcd.setFontFile("/luadb/customer_font_22.bin")

    -- 顶部标题栏
    lcd.fill(0, 0, 320, 60, 0x001F) -- 蓝色背景
    lcd.drawStr(80, 39, "合宙LCD演示系统", 0xFFFF) -- 白色文字


    -- 显示演示内容,使用12号自定义字体
    lcd.setFontFile("/luadb/customer_font_12.bin")

    -- 绘制所有按钮
    for i, btn in ipairs(buttons) do
        local color = btn.color

        -- 绘制按钮背景
        lcd.fill(btn.x1, btn.y1, btn.x2, btn.y2, color)

        -- 绘制按钮文字（居中）
        local text_x = btn.x1 + (btn.x2 - btn.x1) / 2 - 25
        local text_y = btn.y1 + (btn.y2 - btn.y1) / 2

        lcd.drawStr(text_x, text_y, btn.text, 0xFFFF)

        -- 绘制按钮边框
        lcd.drawRectangle(btn.x1, btn.y1, btn.x2, btn.y2, 0x0000)
    end

    -- 底部状态栏
    lcd.fill(0, 380, 320, 480, 0x001F) -- 蓝色背景
    lcd.drawStr(20, 405, "当前页面: 主页", 0xFFFF)
    lcd.drawStr(30, 430, "- 触摸按钮进入功能演示", 0xFFFF)
    lcd.drawStr(30, 450, "- LCD演示: 显示图形绘制功能", 0xFFFF)
    lcd.drawStr(30, 470, "- 自定义字体: 显示外部字体", 0xFFFF)
end

--[[
处理触摸事件；
@api home_page.handle_touch(x, y, switch_page)
@summary 处理主页触摸事件
@number x 触摸点X坐标
@number y 触摸点Y坐标
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false
]]
function home_page.handle_touch(x, y, switch_page)
    log.info("home_page.handle_touch", "x:", x, "y:", y)

    -- 检查触摸是否在按钮区域内
    for i, btn in ipairs(buttons) do
        if x >= btn.x1 and x <= btn.x2 and
            y >= btn.y1 and y <= btn.y2 then
            -- 切换到选中的页面
            switch_page(btn.name)
            return true
        end
    end

    return false
end

--[[
页面进入时重置状态；
@api home_page.on_enter()
@summary 重置页面状态
@return nil
]]
function home_page.on_enter()
    -- 可以在这里执行初始化操作
end

--[[
页面离开时执行清理操作；
@api home_page.on_leave()
@summary 页面离开时清理
@return nil
]]
function home_page.on_leave()
    -- 可以在这里执行清理操作
end

return home_page
