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
3、管理功能按钮的选中状态，支持光标指示器；
4、处理主页面的按键事件，支持BOOT键选择和PWR键确认；

注意：使用自定义字体显示中文

本文件的对外接口有4个：
1、home_page.draw()：绘制主页面UI；
2、home_page.handle_key(key_type, switch_page)：处理按键事件；
3、home_page.on_enter()：页面进入时重置选中状态；
4、home_page.on_leave()：页面离开时执行清理操作；
]]

local home_page = {}

-- 按钮区域定义（调整为2个按钮）
local buttons = {
    { name = "lcd", text = "LCD演示", x1 = 40, y1 = 150, x2 = 140, y2 = 240, color = 0x001F }, -- 蓝色
    { name = "customer_font", text = "自定义字体", x1 = 180, y1 = 150, x2 = 280, y2 = 240, color = 0xF800 } -- 红色
}

-- 当前选中项索引
local selected_index = 1

--[[
绘制光标指示
@local
@return nil
]]
local function draw_cursor()
    local btn = buttons[selected_index]

    -- 在选中按钮周围绘制矩形光标
    lcd.drawRectangle(btn.x1 - 4, btn.y1 - 4, btn.x2 + 4, btn.y2 + 4, 0xFFFF) -- 白色外框
    lcd.drawRectangle(btn.x1 - 3, btn.y1 - 3, btn.x2 + 3, btn.y2 + 3, 0x0000) -- 黑色内框
end

--[[
绘制主页界面；
@api home_page.draw()
@summary 绘制主页面所有UI元素，包括选中指示
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

    -- 绘制光标指示
    draw_cursor()

    -- 底部状态栏
    lcd.fill(0, 380, 320, 480, 0x001F) -- 蓝色背景
    lcd.drawStr(20, 405, "当前页面: 主页", 0xFFFF)
    lcd.drawStr(30, 430, "- BOOT键: 选择选项", 0xFFFF)
    lcd.drawStr(30, 450, "- PWR键: 确认进入", 0xFFFF)
    lcd.drawStr(30, 470, "- 中文仅支持自定义点阵字体", 0xFFFF)
end

--[[
处理主页按键事件；
@api home_page.handle_key(key_type, switch_page)
@summary 处理主页按键事件
@string key_type 按键类型
@valid_values "confirm", "next", "prev"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false
]]
function home_page.handle_key(key_type, switch_page)
    log.info("home_page.handle_key", "key_type:", key_type, "selected_index:", selected_index)

    if key_type == "confirm" then
        -- 确认键：切换到选中的页面
        local btn = buttons[selected_index]
        switch_page(btn.name)
        return true
    elseif key_type == "right" or key_type == "next" then
        -- 向右/下一个
        selected_index = selected_index % #buttons + 1
        return true
    elseif key_type == "left" or key_type == "prev" then
        -- 向左/上一个
        selected_index = (selected_index - 2) % #buttons + 1
        return true
    end
    return false
end

--[[
页面进入时重置选中状态；
@api home_page.on_enter()
@summary 重置选中状态
@return nil
]]
function home_page.on_enter()
    selected_index = 1 -- 默认选中第一个
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

--[[
获取当前选中项信息；
@api home_page.get_selected_info()
@summary 获取当前选中项信息
@return table 包含选中项信息的表
]]
function home_page.get_selected_info()
    local btn = buttons[selected_index]
    return {
        index = selected_index,
        name = btn.name,
        text = btn.text
    }
end

return home_page
