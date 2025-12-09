--[[
@module  customer_font_page
@summary 自定义字体演示模块
@version 1.0
@date    2025.12.3
@author  江访
@usage
本模块为自定义字体演示功能模块，主要功能包括：
1、展示外部自定义字体文件的加载和显示功能；
2、提供多颜色文字显示效果；
3、显示字体使用说明和接口信息；

按键功能：
- PWR键：返回主页
- BOOT键：无功能

对外接口：
1、customer_font_page.draw()：绘制自定义字体演示页面
2、customer_font_page.handle_key()：处理自定义字体页面按键事件
3、customer_font_page.on_leave()：页面离开时恢复系统字体
]]

local customer_font_page = {}

--[[
绘制自定义字体演示页面；
绘制自定义字体演示页面的所有UI元素和字体内容；

@api customer_font_page.draw()
@summary 绘制自定义字体演示页面的所有UI元素和字体内容
@return nil

@usage
-- 在UI主循环中调用
customer_font_page.draw()
]]
function customer_font_page.draw()
    lcd.clear()
    lcd.setFont(lcd.font_opposansm12_chinese)

    -- 设置默认颜色
    lcd.setColor(0xFFFF, 0x0000)

    -- 显示标题（使用系统字体）
    lcd.drawStr(106, 20, "自定义点阵字体演示", 0x0000)
    
    -- 显示操作提示
    lcd.drawStr(20, 40, "按PWR键返回主页", 0x0000)

    -- 设置自定义字体文件
    lcd.setFontFile("/luadb/customer_font_24.bin")

    lcd.drawStr(112, 160, "上海合宙", 0xF800) -- 红色
    lcd.drawStr(120, 200, "LuatOS", 0x07E0) -- 绿色
    lcd.drawStr(100, 240, "演示demo", 0x001F) -- 蓝色

    -- 恢复系统字体显示说明
    lcd.setFont(lcd.font_opposansm12_chinese)
    lcd.setColor(0xFFFF, 0x0000)

    -- 显示说明信息
    lcd.drawStr(20, 320, "- 字体路径: /luadb/customer_font_24.bin", 0x0000)
    -- 显示使用说明
    lcd.drawStr(20, 340, "使用接口:", 0x0000)
    lcd.drawStr(20, 360, "lcd.setFontFile(字体路径)", 0x0000)
    lcd.drawStr(20, 380, "lcd.drawStr(x, y,文本)", 0x0000)
    
    -- 显示当前操作状态
    lcd.drawStr(20, 420, "当前页面: 自定义字体演示", 0x0000)
end

--[[
处理按键事件；
根据按键类型执行相应的操作；

@api customer_font_page.handle_key(key_type, switch_page)
@summary 处理自定义字体页面按键事件
@string key_type 按键类型
@valid_values "pwr_up"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在UI主循环中调用
local handled = customer_font_page.handle_key("pwr_up", switch_page)
]]
function customer_font_page.handle_key(key_type, switch_page)
    log.info("customer_font_page.handle_key", "key_type:", key_type)
    
    if key_type == "pwr_up" then
        -- PWR键：返回首页
        switch_page("home")
        return true
    end
    -- BOOT键无功能
    return false
end

--[[
页面离开时恢复系统字体；
恢复系统默认字体设置；

@api customer_font_page.on_leave()
@summary 恢复系统默认字体设置
@return nil

@usage
-- 在页面切换时调用
customer_font_page.on_leave()
]]
function customer_font_page.on_leave()
    -- 恢复使用12号中文字体
    lcd.setFont(lcd.font_opposansm12_chinese)
    log.info("customer_font_page", "已恢复系统字体")
end

return customer_font_page