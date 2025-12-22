--[[
@module  gtfont_page
@summary U8G2 GTFont演示页面模块 - 128x64屏幕
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为GTFont演示页面模块，核心业务逻辑为：
1、展示GTFont外置字库的字体大小切换功能；
2、显示当前选中的字体大小；
3、提供返回按钮和字体大小切换按钮；
4、支持BOOT键和PWR键的导航操作；

本文件的对外接口有4个：
1、gtfont_page.draw()：绘制页面内容；
2、gtfont_page.handle_key(key_type)：处理按键事件；
3、gtfont_page.on_enter()：页面进入回调；
4、gtfont_page.on_leave()：页面离开回调；
]]

local gtfont_page = {}

-- 当前选中按钮的索引（1:返回, 2:切换）
local selected_index = 1

-- 字体大小选项数组
local size_options = { 12, 14, 16, 18, 20 }

-- 当前字体大小在数组中的索引
local size_index = 1

--[[
@function get_current_size
@summary 获取当前选中的字体大小
@return number 当前字体大小
]]
local function get_current_size()
    return size_options[size_index]
end

--[[
@api draw()
@summary 绘制GTFont演示页面内容
@return 无返回值
@usage
-- 在UI主循环中调用
gtfont_page.draw()
]]
function gtfont_page.draw()
    -- 标题
    u8g2.SetFont(u8g2.font_6x10)
    u8g2.DrawUTF8("GTFont页", 34, 10)

    -- 字体大小显示
    u8g2.DrawUTF8("字体:", 5, 28)

    local current_size = get_current_size()

    -- 使用GTFont绘制字体大小
    u8g2.drawGtfontUtf8(tostring(current_size) .. "号", current_size, 40, 16)

    -- 示例文本区域
    u8g2.DrawUTF8("示例文本:需外置字库", 5, 60)

    -- 按钮区域（垂直排列）
    if selected_index == 1 then
        -- 返回按钮：选中状态
        u8g2.DrawButtonUTF8("返回", 5, 10, u8g2.BTN_INV + u8g2.BTN_BW1, 0, 0, 0)
    else
        -- 返回按钮：未选中状态
        u8g2.DrawButtonUTF8("返回", 5, 10, u8g2.BTN_BW1, 0, 0, 0)
    end

    if selected_index == 2 then
        -- 切换按钮：选中状态
        u8g2.DrawButtonUTF8("切换", 99, 10, u8g2.BTN_INV + u8g2.BTN_BW1, 0, 0, 0)
    else
        -- 切换按钮：未选中状态
        u8g2.DrawButtonUTF8("切换", 99, 10, u8g2.BTN_BW1, 0, 0, 0)
    end
end

--[[
@api handle_key(key_type)
@summary 处理按键事件，实现字体大小切换和页面导航
@param string key_type 按键类型，可选值：
  - "confirm"：确认键，执行当前选中按钮的功能
  - "next"：切换到下一个按钮
  - "prev"：切换到上一个按钮
@return bool 是否已处理该按键，true表示已处理
@usage
-- 在UI主循环中调用
local handled = gtfont_page.handle_key("confirm")
]]
function gtfont_page.handle_key(key_type)
    log.info("gtfont_page.handle_key", "key_type:", key_type)

    if key_type == "confirm" then
        -- 确认键：执行当前选中按钮的功能
        if selected_index == 1 then
            -- 返回按钮：返回首页
            switch_page("home")
        elseif selected_index == 2 then
            -- 切换按钮：切换到下一个字体大小
            size_index = size_index % #size_options + 1
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
@summary 页面进入时的初始化操作，重置选中项和字体大小索引
@return 无返回值
@usage
-- 在页面切换时自动调用
gtfont_page.on_enter()
]]
function gtfont_page.on_enter()
    -- 页面进入时初始化
    selected_index = 1 -- 默认选中返回按钮
    size_index = 1     -- 默认使用第一个字体大小
end

--[[
@api on_leave()
@summary 页面离开时的清理操作
@return 无返回值
@usage
-- 在页面切换时自动调用
gtfont_page.on_leave()
]]
function gtfont_page.on_leave()
    -- 页面离开时的清理操作
    -- 当前无需特殊清理
end

return gtfont_page
