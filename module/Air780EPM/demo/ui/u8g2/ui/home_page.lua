--[[
@module  home_page
@summary U8G2主页模块 - 128x64屏幕
@version 1.0
@date    2025.12.23
@author  江访
@usage
本文件为主页显示模块，核心业务逻辑为：
1、显示主菜单，包含两个选项：组件演示、内置字体；
2、处理BOOT键和PWR键的导航和确认操作；
3、管理当前选中项状态；

本文件的对外接口有4个：
1、home_page.draw()：绘制页面内容；
2、home_page.handle_key(key_type)：处理按键事件；
3、home_page.on_enter()：页面进入回调；
4、home_page.on_leave()：页面离开回调；
]]

local home_page = {}

-- 菜单项
local menu_items = {
    {name = "component", text = "1.Component Demo", x = 10, y = 22},
    {name = "default_font", text = "2.Built-in Font", x = 10, y = 40}
}

local selected_index = 1

--[[
@api draw()
@summary 绘制主页内容
@return 无返回值
@usage
-- 在UI主循环中调用
home_page.draw()
]]
function home_page.draw()

    -- 绘制按键提示
    u8g2.DrawUTF8("BOOT:Select", 0, 10)
    u8g2.DrawUTF8("PWR:Confirm", 0, 58)
    
    -- 绘制菜单项
    for i, item in ipairs(menu_items) do
        if i == selected_index then
            -- 选中状态
            u8g2.DrawButtonUTF8(item.text, item.x, item.y, 
                u8g2.BTN_INV + u8g2.BTN_BW1, 110, 2, 0)
        else
            -- 未选中状态
            u8g2.DrawButtonUTF8(item.text, item.x, item.y, 
                u8g2.BTN_BW1, 110, 2, 0)
        end
    end
end

--[[
@api handle_key(key_type)
@summary 处理按键事件
@param string key_type 按键类型，可选值："confirm"、"next"、"prev"
@return bool 是否已处理该按键
@usage
-- 在UI主循环中调用
home_page.handle_key("confirm")
]]
function home_page.handle_key(key_type)
    log.info("home_page.handle_key", "key_type:", key_type, "selected_index:", selected_index)
    
    if key_type == "confirm" then
        -- 确认键：切换到选中的页面
        local item = menu_items[selected_index]
        switch_page(item.name)
        return true
    elseif key_type == "next" then
        -- 向下选择
        selected_index = selected_index % #menu_items + 1
        return true
    elseif key_type == "prev" then
        -- 向上选择
        selected_index = (selected_index - 2) % #menu_items + 1
        return true
    end
    
    return false
end

--[[
@api on_enter()
@summary 页面进入时的初始化操作
@return 无返回值
@usage
-- 在页面切换时自动调用
home_page.on_enter()
]]
function home_page.on_enter()
    selected_index = 1  -- 重置选中项
end

--[[
@api on_leave()
@summary 页面离开时的清理操作
@return 无返回值
@usage
-- 在页面切换时自动调用
home_page.on_leave()
]]
function home_page.on_leave()
    -- 页面离开时的清理操作
end

return home_page