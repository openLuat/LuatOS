--[[
@module  home_page
@summary 主页模块，提供应用入口和导航功能（触摸版）
@version 1.1
@date    2026.06.24
@author  江访
@usage
本模块为主页模块，主要功能包括：
1、提供应用入口和导航功能；
2、显示系统标题和操作提示；
3、提供三个功能按钮：摄像头预览、LCD演示、自定义字体；
4、处理主页面的触摸事件；

注意：使用自定义字体显示中文

本文件的对外接口有3个：
1、home_page.draw()：绘制主页面UI；
2、home_page.handle_touch()：处理触摸事件；
3、home_page.on_enter()：页面进入时重置状态；
]]

local home_page = {}

-- 按钮区域定义（竖排三等宽居中）
local buttons = {
    { name = "lcd",              text = "LCD演示",        x1 = 60, y1 = 100, x2 = 260, y2 = 180, color = 0x001F },
    { name = "camera_preview",   text = "摄像头:点击拍照",  x1 = 60, y1 = 200, x2 = 260, y2 = 280, color = 0xFCC0 },
    { name = "customer_font",    text = "自定义字体",     x1 = 60, y1 = 300, x2 = 260, y2 = 380, color = 0x07E0 }
}

local title = "合宙lcd演示系统"
local content1 = "本页面使用的是12号自定义点阵字体"

-- Air780EPM 使用自定义点阵字体显示中文
local function set_title_font()
    lcd.setFontFile("/luadb/customer_font_22.bin")
end

local function set_body_font()
    lcd.setFontFile("/luadb/customer_font_12.bin")
end


--[[
绘制主页界面；
@api home_page.draw()
@summary 绘制主页面所有UI元素
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
end

function home_page.on_leave()
end

return home_page
