--[[
@module  home_page
@summary 主页模块，提供应用入口和导航功能
@version 1.0
@date    2025.12.3
@author  江访
@usage
本模块为主页模块，主要功能包括：
1、提供应用入口和导航功能；
2、显示系统标题和操作提示；
3、管理三个功能按钮的选中状态；
4、处理主页面的按键事件；

对外接口：
1、home_page.draw()：绘制主页面所有UI元素，包括选中指示
2、home_page.handle_key()：处理主页面按键事件
3、home_page.on_enter()：页面进入时重置选中状态
4、home_page.on_leave()：页面离开时执行清理操作
]]

local home_page = {}


-- 按钮区域定义
local buttons = {
    {name = "lcd", text = "lcd核心库演示", x1 = 10, y1 = 350, x2 = 100, y2 = 420, color = 0x001F},
    {name = "gtfont", text = "矢量字体芯片", x1 = 115, y1 = 350, x2 = 205, y2 = 420, color = 0xF800},
    {name = "customer_font", text = "自定义字体", x1 = 220, y1 = 350, x2 = 310, y2 = 420, color = 0x07E0}
}

-- 当前选中项索引
local selected_index = 1

local title = "合宙lcd演示系统"
local content1 = "本页面使用的是系统内置的12号中文点阵字体"
local hint = "boot键:选择 pwr键:确认"

--[[
绘制光标指示
@local
@return nil
]]
local function draw_cursor()
    local btn = buttons[selected_index]
    
    -- 在选中按钮周围绘制矩形光标
    lcd.drawRectangle(btn.x1 - 2, btn.y1 - 2, btn.x2 + 2, btn.y2 + 2, 0x3186)  -- 蓝色外框
    lcd.drawRectangle(btn.x1 - 1, btn.y1 - 1, btn.x2 + 1, btn.y2 + 1, 0x0000)  -- 黑色内框
end

--[[
绘制主页界面；
绘制主页面所有UI元素，包括选中指示；

@api home_page.draw()
@summary 绘制主页面所有UI元素，包括选中指示
@return nil

@usage
-- 在UI主循环中调用
home_page.draw()
]]
function home_page.draw()
    lcd.clear()
    lcd.setColor(0xFFFF, 0x0000)
    lcd.setFont(lcd.font_opposansm12_chinese)

    -- 显示标题
    lcd.drawStr(106, 30, title, 0x0000)

    -- 显示说明文字
    lcd.drawStr(46, 48, content1, 0x0000)
    lcd.drawStr(86, 66, hint, 0x0000)

    -- 绘制所有按钮
    for i, btn in ipairs(buttons) do
        local color = btn.color
        if i == selected_index then
            -- 选中状态：颜色稍微变亮
            color = color + 0x0842
        end
        
        lcd.fill(btn.x1, btn.y1, btn.x2, btn.y2, color)
        
        -- 根据按钮调整文字位置
        if btn.name == "lcd" then
            lcd.drawStr(btn.x1 + 5, btn.y1 + 30, "lcd核心库演示", 0xFFFF)
        elseif btn.name == "gtfont" then
            lcd.drawStr(btn.x1 + 28, btn.y1 + 20, "外部", 0xFFFF)
            lcd.drawStr(btn.x1 + 4, btn.y1 + 40, "矢量字体芯片", 0xFFFF)
        elseif btn.name == "customer_font" then
            lcd.drawStr(btn.x1 + 15, btn.y1 + 30, "自定义字体", 0xFFFF)
        end
    end

    -- 绘制光标指示
    draw_cursor()
end

--[[
处理主页按键事件；
根据按键类型执行相应的操作；

@api home_page.handle_key(key_type, switch_page)
@summary 处理主页按键事件
@string key_type 按键类型
@valid_values "confirm", "next", "prev", "back"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = home_page.handle_key("next", switch_page)
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
    elseif key_type == "back" then
        -- 返回键：可以执行其他操作或提示
        return false
    end
    return false
end

--[[
页面进入时重置选中状态；
重置选中状态为第一个按钮；

@api home_page.on_enter()
@summary 重置选中状态
@return nil

@usage
-- 在页面切换时调用
home_page.on_enter()
]]
function home_page.on_enter()
    selected_index = 1  -- 默认选中第一个
end

--[[
获取当前选中项信息；
用于调试或状态查询；

@api home_page.get_selected_info()
@summary 获取当前选中项信息
@return table 包含选中项信息的表
@field index number 当前选中项的索引
@field name string 当前选中项的名称
@field text string 当前选中项的显示文本

@usage
-- 获取当前选中项信息
local info = home_page.get_selected_info()
log.info("当前选中", info.name, info.text)
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