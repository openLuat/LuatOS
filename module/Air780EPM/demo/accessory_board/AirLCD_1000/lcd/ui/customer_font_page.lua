--[[
@module  customer_font_page
@summary 自定义字体演示模块，展示外部点阵字体的加载和显示功能
@version 1.0
@date    2025.12.8
@author  江访
@usage
本模块为自定义字体演示功能模块，核心业务逻辑为：
1、展示外部自定义字体文件的加载和显示功能，支持12号和22号字体；
2、提供多颜色文字显示效果，支持红、绿、蓝三色文字；
3、显示字体使用说明和设备支持信息；
4、展示字体使用接口示例和文件路径信息；

注意：当前设备仅支持自定义点阵字体显示中文

本文件的对外接口有3个：
1、customer_font_page.draw()：绘制自定义字体演示页面；
2、customer_font_page.handle_key(key_type, switch_page)：处理按键事件；
3、customer_font_page.on_leave()：页面离开时恢复默认字体；
]]
local customer_font_page = {}

--[[
绘制自定义字体演示页面；
@api customer_font_page.draw()
@summary 绘制自定义字体演示页面的所有UI元素和字体内容
@return nil
]]
function customer_font_page.draw()
    lcd.clear()

    -- 显示标题，使用22号自定义字体
    -- 设置背景颜色
    lcd.setColor(0xFFFF, 0x0000)
    lcd.setFontFile("/luadb/customer_font_22.bin")

    -- 显示标题区域
    lcd.fill(0, 0, 320, 40, 0x001F) -- 蓝色标题栏    lcd.setColor(0xFFFF, 0x0000)

    -- 显示标题
    lcd.drawStr(70, 30, "自定义点阵字体演示", 0xFFFF)


    -- 显示演示内容,使用12号自定义字体
    lcd.setFontFile("/luadb/customer_font_12.bin")

    -- 字体支持说明区域（带背景色）
    lcd.fill(15, 60, 305, 155, 0xF7DE)          -- 浅灰色背景
    lcd.drawRectangle(15, 60, 305, 155, 0x8410) -- 边框

    -- 显示字体支持说明
    lcd.drawStr(30, 80, "当前设备字体支持:", 0x0000)
    lcd.drawStr(40, 105, "- 仅支持自定义字体", 0x0000)
    lcd.drawStr(40, 120, "- 不支持内置12号中文", 0x0000)
    lcd.drawStr(40, 135, "- 不支持GTFont矢量字体", 0x0000)

    lcd.drawLine(20, 165, 300, 165, 0x8410)

    -- 设置22号自定义字体文件显示示例文字
    lcd.setFontFile("/luadb/customer_font_22.bin")

    -- 示例文字区域（居中显示）
    lcd.drawStr(100, 200, "上海合宙", 0xF800) -- 红色
    lcd.drawStr(105, 230, "LuatOS", 0x07E0) -- 绿色
    lcd.drawStr(95, 260, "演示demo", 0x001F) -- 蓝色

    -- 恢复12号字体显示说明
    lcd.setFontFile("/luadb/customer_font_12.bin")
    lcd.setColor(0xFFFF, 0x0000)

    -- 字体文件信息区域
    lcd.drawLine(20, 280, 300, 280, 0x8410)
    lcd.drawStr(20, 300, "字体文件信息:", 0x0000)
    lcd.drawStr(30, 325, "- 12号字体: /luadb/customer_font_12.bin", 0x0000)
    lcd.drawStr(30, 350, "- 22号字体: /luadb/customer_font_22.bin", 0x0000)

    -- 显示使用接口
    lcd.drawStr(20, 380, "使用接口:", 0x0000)
    lcd.drawStr(35, 405, "- lcd.setFontFile(字体路径)", 0x0000)
    lcd.drawStr(35, 425, "- lcd.drawStr(x, y, 文本, 颜色)", 0x0000)

    -- 底部状态栏
    lcd.fill(0, 440, 320, 480, 0x001F) -- 蓝色背景
    lcd.drawStr(20, 465, "按PWR键返回主页", 0xFFFF)
end

--[[
处理按键事件；
@api customer_font_page.handle_key(key_type, switch_page)
@summary 处理自定义字体页面按键事件
@string key_type 按键类型
@valid_values "pwr_up"
@function switch_page 页面切换回调函数
@return bool 事件处理成功返回true，否则返回false
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
页面离开时恢复默认字体；
@api customer_font_page.on_leave()
@summary 恢复12号自定义字体
@return nil
]]
function customer_font_page.on_leave()
    -- 恢复使用12号自定义字体
    lcd.setFontFile("/luadb/customer_font_12.bin")
    log.info("customer_font_page", "已恢复12号自定义字体")
end

return customer_font_page
