--[[
@module  home_page
@summary 主页模块，提供应用入口和导航功能
@version 1.1
@date    2026.06.24
@author  江访
@usage
本模块为主页模块，核心业务逻辑为：
1、提供应用入口和导航功能；
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

-- 按钮区域定义（竖排三等宽居中）
local buttons = {
    {name = "lcd",              text = "LCD演示",        x1 = 60, y1 = 100, x2 = 260, y2 = 180, color = 0x001F},
    {name = "camera_preview",   text = "摄像头:点击拍照",  x1 = 60, y1 = 200, x2 = 260, y2 = 280, color = 0xFCC0},
    {name = "customer_font",    text = "自定义字体",     x1 = 60, y1 = 300, x2 = 260, y2 = 380, color = 0x07E0}
}

-- 当前选中项索引
local selected_index = 1

local title = "合宙lcd演示系统"
local content1 = "本页面使用的是12号自定义点阵字体"
local hint = "boot键:选择 pwr键:确认"

-- Air780EPM 使用自定义点阵字体显示中文
local function set_title_font()
    lcd.setFontFile("/luadb/customer_font_22.bin")
end

local function set_body_font()
    lcd.setFontFile("/luadb/customer_font_12.bin")
end


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
@api home_page.draw()
@summary 绘制主页面所有UI元素，包括选中指示
@return nil
]]
function home_page.draw()
    lcd.clear()
    lcd.setColor(0xFFFF, 0x0000)

    -- 显示标题，使用22号自定义字体
    set_title_font()
    lcd.drawStr(106, 30, title, 0x0000)

    -- 显示说明文字，使用12号自定义字体
    set_body_font()
    lcd.drawStr(46, 50, content1, 0x0000)

    -- 绘制所有按钮
    for i, btn in ipairs(buttons) do
        local color = btn.color
        if i == selected_index then
            -- 选中状态：颜色稍微变亮
            color = color + 0x0842
        end

        lcd.fill(btn.x1, btn.y1, btn.x2, btn.y2, color)

        -- 绘制按钮文字
        if btn.name == "lcd" then
            lcd.drawStr(130, 138, "LCD演示", 0xFFFF)
        elseif btn.name == "camera_preview" then
            lcd.drawStr(120, 238, "摄像头:点击拍照", 0xFFFF)
        elseif btn.name == "customer_font" then
            lcd.drawStr(125, 338, "自定义字体", 0xFFFF)
        end
    end

    -- 绘制光标指示
    draw_cursor()
end

--[[
处理主页按键事件；
@api home_page.handle_key(key_type, switch_page)
@summary 处理主页按键事件
@string key_type 按键类型
@valid_values "confirm", "next", "prev", "back"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false
]]
function home_page.handle_key(key_type, switch_page)
    log.info("home_page.handle_key", "key_type:", key_type, "selected_index:", selected_index)

    if key_type == "confirm" then
        local btn = buttons[selected_index]
        switch_page(btn.name)
        return true
    elseif key_type == "right" or key_type == "next" then
        selected_index = selected_index % #buttons + 1
        return true
    elseif key_type == "left" or key_type == "prev" then
        selected_index = (selected_index - 2) % #buttons + 1
        return true
    elseif key_type == "back" then
        return false
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
    selected_index = 1
end

function home_page.on_leave()
end

return home_page
