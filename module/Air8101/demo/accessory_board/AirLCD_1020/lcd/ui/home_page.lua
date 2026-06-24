--[[
@module  home_page
@summary 主页模块，提供应用入口和导航功能
@version 1.1
@date    2025.12.1
@author  江访
@usage
本模块为主页面功能模块，主要功能包括：
1、绘制主页面UI界面，显示应用标题和功能介绍；
2、提供功能按钮：LCD演示、矢量字体演示、自定义字体演示、DVP拍照、USB预览；
3、处理主页面的触摸事件，实现页面导航；

对外接口：
1、home_page.draw()：绘制主页界面
2、home_page.handle_touch()：处理主页触摸事件
]]

local home_page = {}

-- 屏幕尺寸
local width, height

local center_x

-- 按钮区域定义（适配800x480）
local buttons = {
    lcd_page = { x1 = 80, y1 = 330, x2 = 340, y2 = 380 },
    customer_font_page = { x1 = 420, y1 = 330, x2 = 700, y2 = 380 },
    dvp_camera = { x1 = 80, y1 = 395, x2 = 340, y2 = 445 },
    usb_camera = { x1 = 420, y1 = 395, x2 = 700, y2 = 445 },
}

local title = "合宙LCD演示系统"
local content1 = "本页面使用的是系统内置的12号中文点阵字体"

--[[
绘制主页界面；

@api home_page.draw()
@summary 绘制主页面所有UI元素
@return nil
]]
function home_page.draw()
    lcd.clear()
    lcd.setColor(0xFFFF, 0x0000)
    lcd.setFont(lcd.font_opposansm12_chinese)

    width, height = lcd.getSize()
    center_x = math.floor(width / 2)

    -- 显示标题（居中）
    log.info("center_x", width, height, center_x)
    lcd.drawStr(center_x - 70, 50, title, 0x0000)

    -- 显示说明文字
    lcd.drawStr(center_x - 130, 90, content1, 0x0000)

    -- 添加演示说明
    lcd.drawStr(center_x - 75, 120, "屏幕尺寸: " .. width .. "x" .. height, 0x0000)

    -- 绘制LCD演示按钮
    lcd.fill(buttons.lcd_page.x1, buttons.lcd_page.y1,
        buttons.lcd_page.x2, buttons.lcd_page.y2, 0x001F)
    lcd.setColor(0xFFFF, 0x0000)
    lcd.drawStr(buttons.lcd_page.x1 + 85, buttons.lcd_page.y1 + 30, "LCD演示", 0xFFFF)

    -- 绘制自定义字体演示按钮
    lcd.fill(buttons.customer_font_page.x1, buttons.customer_font_page.y1,
        buttons.customer_font_page.x2, buttons.customer_font_page.y2, 0x07E0)
    lcd.drawStr(buttons.customer_font_page.x1 + 75, buttons.customer_font_page.y1 + 30, "自定义字体演示", 0xFFFF)

    -- 绘制DVP拍照按钮
    lcd.fill(buttons.dvp_camera.x1, buttons.dvp_camera.y1,
        buttons.dvp_camera.x2, buttons.dvp_camera.y2, 0xF800)
    lcd.drawStr(buttons.dvp_camera.x1 + 65, buttons.dvp_camera.y1 + 30, "DVP拍照", 0xFFFF)

    -- 绘制USB预览按钮
    lcd.fill(buttons.usb_camera.x1, buttons.usb_camera.y1,
        buttons.usb_camera.x2, buttons.usb_camera.y2, 0xF800)
    lcd.drawStr(buttons.usb_camera.x1 + 65, buttons.usb_camera.y1 + 30, "USB预览", 0xFFFF)
end

--[[
处理主页触摸事件；

@api home_page.handle_touch(x, y, switch_page)
@number x 触摸点X坐标，范围0-799
@number y 触摸点Y坐标，范围0-479
@function switch_page 页面切换回调函数
@return boolean 事件处理成功返回true，否则返回false
]]
function home_page.handle_touch(x, y, switch_page)
    -- 检查LCD演示按钮
    if x >= buttons.lcd_page.x1 and x <= buttons.lcd_page.x2 and
        y >= buttons.lcd_page.y1 and y <= buttons.lcd_page.y2 then
        switch_page("lcd")
        return true
    end

    -- 检查自定义字体演示按钮
    if x >= buttons.customer_font_page.x1 and x <= buttons.customer_font_page.x2 and
        y >= buttons.customer_font_page.y1 and y <= buttons.customer_font_page.y2 then
        switch_page("customer_font_page")
        return true
    end

    -- 检查DVP拍照按钮
    if x >= buttons.dvp_camera.x1 and x <= buttons.dvp_camera.x2 and
        y >= buttons.dvp_camera.y1 and y <= buttons.dvp_camera.y2 then
        switch_page("dvp_camera")
        return true
    end

    -- 检查USB预览按钮
    if x >= buttons.usb_camera.x1 and x <= buttons.usb_camera.x2 and
        y >= buttons.usb_camera.y1 and y <= buttons.usb_camera.y2 then
        switch_page("usb_camera")
        return true
    end

    return false
end

return home_page
