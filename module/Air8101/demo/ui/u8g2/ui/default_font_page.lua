--[[
@module  default_font_page
@summary U8G2内置字体演示页面模块 - 128x64屏幕
@version 1.0
@date    2025.12.11
@author  江访
@usage
本文件为默认字体演示页面模块，核心业务逻辑为：
1、展示U8G2内置字体的显示效果；
2、显示固定文本内容和当前系统时间；
3、提供返回首页的功能；
4、支持切换键（GPIO8）和确认键（GPIO5）的导航操作；

本文件的对外接口有4个：
1、default_font_page.draw()：绘制页面内容；
2、default_font_page.handle_key(key_type)：处理按键事件；
3、default_font_page.on_enter()：页面进入回调；
4、default_font_page.on_leave()：页面离开回调；
]]

local default_font_page = {}

-- 当前选中项的索引（仅有一个返回按钮）
local selected_index = 1

--[[
@api draw()
@summary 绘制默认字体演示页面内容
@return 无返回值
@usage
-- 在UI主循环中调用
default_font_page.draw()
]]
function default_font_page.draw()
    -- 标题
    u8g2.DrawUTF8("内置字体页", 35, 10)

    -- 字体演示（居中显示）
    u8g2.DrawUTF8("合宙LuatOS", 25, 27)
    u8g2.DrawUTF8("U8G2演示程序", 20, 42)
    u8g2.DrawUTF8(os.date("%Y-%m-%d %H:%M:%S"), 0, 58)

    -- 按钮区域
    if selected_index == 1 then
        -- 返回按钮：选中状态
        u8g2.DrawButtonUTF8("返回", 5, 10, u8g2.BTN_INV + u8g2.BTN_BW1, 0, 2, 0)
    else
        -- 返回按钮：未选中状态
        u8g2.DrawButtonUTF8("返回", 5, 10, u8g2.BTN_BW1, 0, 2, 0)
    end
end

--[[
@api handle_key(key_type)
@summary 处理按键事件，实现页面导航
@param string key_type 按键类型，可选值：
  - "confirm"：确认键，返回首页
  - "next"：切换选中状态（仅有一个按钮，无实际效果）
  - "prev"：切换选中状态（仅有一个按钮，无实际效果）
@return bool 是否已处理该按键，true表示已处理
@usage
-- 在UI主循环中调用
local handled = default_font_page.handle_key("confirm")
]]
function default_font_page.handle_key(key_type)
    log.info("default_font_page.handle_key", "key_type:", key_type)

    if key_type == "confirm" then
        -- 确认键：返回首页
        switch_page("home")
        return true
    elseif key_type == "next" or key_type == "prev" then
        -- 切换选中项（只有一个按钮，所以切换无实际效果）
        -- 但为了保持接口一致性，仍然返回true表示已处理
        return true
    end

    return false
end

--[[
@api on_enter()
@summary 页面进入时的初始化操作，重置选中项和设置帧更新时间
@return 无返回值
@usage
-- 在页面切换时自动调用
default_font_page.on_enter()
]]
function default_font_page.on_enter()
    -- 页面进入时初始化
    selected_index = 1
    -- 设置较短的帧更新时间，使时间显示能够实时更新
    frame_time = 300  -- 300ms
end

--[[
@api on_leave()
@summary 页面离开时的清理操作，恢复默认帧更新时间
@return 无返回值
@usage
-- 在页面切换时自动调用
default_font_page.on_leave()
]]
function default_font_page.on_leave()
    -- 页面离开时的清理操作
    -- 恢复默认的帧更新时间（60秒）
    frame_time = 60 * 1000
end

return default_font_page