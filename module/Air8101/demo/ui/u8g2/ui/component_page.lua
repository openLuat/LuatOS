--[[
@module  component_page
@summary U8G2组件演示页面模块 - 128x64屏幕
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为组件演示页面模块，核心业务逻辑为：
1、展示U8G2图形组件的绘制能力；
2、显示进度条和基本图形（圆形、矩形、三角形等）；
3、提供进度调整功能和返回首页功能；
4、支持切换键（GPIO8）和确认键（GPIO5）的导航操作；

本文件的对外接口有4个：
1、component_page.draw()：绘制页面内容；
2、component_page.handle_key(key_type)：处理按键事件；
3、component_page.on_enter()：页面进入回调；
4、component_page.on_leave()：页面离开回调；
]]

local component_page = {}

-- 进度条当前值（0-100）
local progress_value = 30

-- 当前选中按钮的索引（1:返回, 2:+10%）
local selected_index = 1

--[[
@api draw()
@summary 绘制组件演示页面内容
@return 无返回值
@usage
-- 在UI主循环中调用
component_page.draw()
]]
function component_page.draw()
    -- 标题
    u8g2.SetFont(u8g2.font_6x10)
    u8g2.DrawUTF8("组件页", 35, 10)
    
    -- 进度条区域
    u8g2.DrawUTF8("进度条:", 5, 25)
    
    -- 进度条背景（更大）
    u8g2.DrawFrame(42, 15, 50, 12)
    
    -- 进度条前景
    local fill_width = math.floor(50 * progress_value / 100)
    u8g2.DrawBox(41, 15, fill_width, 12)
    
    -- 进度文本
    u8g2.DrawUTF8(progress_value .. "%", 95,25)
    
    -- 图形演示区域
    u8g2.DrawUTF8("图形:", 5, 40)
    
    -- 绘制基本图形（增加间距）
    u8g2.DrawCircle(40, 36, 5, u8g2.DRAW_ALL)
    u8g2.DrawDisc(60, 36, 5, u8g2.DRAW_ALL)
    u8g2.DrawFrame(75, 31, 10, 10)
    u8g2.DrawBox(90, 31, 10, 10)
    u8g2.DrawTriangle(105, 40, 110, 30, 115, 40)
    
    -- 按钮区域（布局更宽松）
    if selected_index == 1 then
        -- 返回按钮：选中状态
        u8g2.DrawButtonUTF8("返回", 10, 58, u8g2.BTN_INV + u8g2.BTN_BW1, 0, 2, 0)
    else
        -- 返回按钮：未选中状态
        u8g2.DrawButtonUTF8("返回", 10, 58, u8g2.BTN_BW1, 0, 2, 0)
    end
    
    if selected_index == 2 then
        -- +10%按钮：选中状态
        u8g2.DrawButtonUTF8("+10%", 70, 58, u8g2.BTN_INV + u8g2.BTN_BW1, 0, 2, 0)
    else
        -- +10%按钮：未选中状态
        u8g2.DrawButtonUTF8("+10%", 70, 58, u8g2.BTN_BW1, 0, 2, 0)
    end
end

--[[
@api handle_key(key_type)
@summary 处理按键事件，实现进度调整和页面导航
@param string key_type 按键类型，可选值：
  - "confirm"：确认键，执行当前选中按钮的功能
  - "next"：切换到下一个按钮
  - "prev"：切换到上一个按钮
@return bool 是否已处理该按键，true表示已处理
@usage
-- 在UI主循环中调用
local handled = component_page.handle_key("confirm")
]]
function component_page.handle_key(key_type)
    log.info("component_page.handle_key", "key_type:", key_type)
    
    if key_type == "confirm" then
        -- 确认键：执行当前选中按钮的功能
        if selected_index == 1 then
            -- 返回按钮：返回首页
            switch_page("home")
        elseif selected_index == 2 then
            -- +10%按钮：增加进度值，最大不超过100%
            progress_value = math.min(100, progress_value + 10)
        end
        return true
    elseif key_type == "next" then
        -- 切换到下一个按钮
        selected_index = selected_index % 2 + 1
        return true
    elseif key_type == "prev" then
        -- 切换到上一个按钮
        selected_index = (selected_index - 2) % 2 + 1
        return true
    end
    
    return false
end

--[[
@api on_enter()
@summary 页面进入时的初始化操作，重置选中项和进度值
@return 无返回值
@usage
-- 在页面切换时自动调用
component_page.on_enter()
]]
function component_page.on_enter()
    -- 页面进入时初始化
    selected_index = 1  -- 默认选中返回按钮
end

--[[
@api on_leave()
@summary 页面离开时的清理操作
@return 无返回值
@usage
-- 在页面切换时自动调用
component_page.on_leave()
]]
function component_page.on_leave()
    -- 页面离开时的清理操作
    -- 当前无需特殊清理
end

return component_page