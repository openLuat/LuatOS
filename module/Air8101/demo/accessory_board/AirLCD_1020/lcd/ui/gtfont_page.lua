--[[
@module  gtfont_page
@summary GTFont矢量字体演示模块
@version 1.1
@date    2025.12.1
@author  江访
@usage
本模块为GTFont矢量字体演示功能模块，主要功能包括：
1、展示AirFONTS_1000矢量字库小板的字体显示功能；
2、支持10-192号字体大小动态变化演示；
3、支持灰度模式和常规模式切换；
4、提供倒计时和字体大小变化两种演示阶段；

对外接口：
1、gtfont_page.draw()：绘制GTFont演示页面
2、gtfont_page.handle_touch()：处理GTFont页面触摸事件
3、gtfont_page.on_enter()：页面进入时状态重置
]]
local gtfont_page = {}

-- 按钮区域定义
local back_button = { x1 = 10, y1 = 10, x2 = 80, y2 = 50 }
local switch_button = { x1 = 650, y1 = 10, x2 = 740, y2 = 50 }

-- 字体显示状态
local font_demo_state = {
    use_gray = true,                   -- 默认为灰度模式
    demo_phase = 1,                    -- 演示阶段
    last_update = 0,
    update_interval = 1000,            -- 倒计时更新间隔
    font_update_interval = 20,         -- 字体更新间隔
    countdown = 18,                     -- 倒计时
    current_size = 16,                 -- 当前字体大小
    color_phase = 1,                   -- 颜色阶段
}

--[[
绘制开关按钮
@local
@return nil
]]
local function draw_switch_button()
    -- 按钮背景
    lcd.fill(switch_button.x1, switch_button.y1, switch_button.x2, switch_button.y2, 0xC618)

    -- 开关指示器
    if font_demo_state.use_gray then
        -- 灰度模式，左边填充
        lcd.fill(switch_button.x1, switch_button.y1,
            switch_button.x1 + (switch_button.x2 - switch_button.x1) / 2,
            switch_button.y2, 0x07E0)
    else
        -- 常规模式，右边填充
        lcd.fill(switch_button.x1 + (switch_button.x2 - switch_button.x1) / 2,
            switch_button.y1, switch_button.x2, switch_button.y2, 0x07E0)
    end

    -- 按钮文字
    lcd.setColor(0xFFFF, 0x0000)
    lcd.setFont(lcd.font_opposansm12_chinese)
    lcd.drawStr(switch_button.x1 + 10, switch_button.y1 + 25, "灰度", 0x0000)
    lcd.drawStr(switch_button.x1 + (switch_button.x2 - switch_button.x1) / 2 + 10,
        switch_button.y1 + 25, "常规", 0x0000)
end

--[[
绘制返回按钮
@local
@return nil
]]
local function draw_back_button()
    lcd.fill(back_button.x1, back_button.y1, back_button.x2, back_button.y2, 0xC618)
    lcd.setColor(0xFFFF, 0x0000)
    lcd.setFont(lcd.font_opposansm12_chinese)
    lcd.drawStr(back_button.x1 + 25, back_button.y1 + 25, "返回", 0x0000)
end

--[[
绘制倒计时阶段
@local
@return boolean 是否完成倒计时
]]
local function draw_countdown_phase()
    local _, current_time = mcu.ticks2(1)
    
    if current_time - font_demo_state.last_update > font_demo_state.update_interval then
        font_demo_state.countdown = font_demo_state.countdown - 1
        font_demo_state.last_update = current_time
        
        if font_demo_state.countdown <= 0 then
            font_demo_state.demo_phase = 2
            font_demo_state.current_size = 16
            font_demo_state.color_phase = 1
            font_demo_state.last_update = current_time
            return true
        end
    end
    
    -- 设置背景色为白色，文字的前景色为黑色
    lcd.setColor(0xFFFF, 0x0000)
    if font_demo_state.use_gray then
        lcd.drawGtfontUtf8Gray("AirFONTS_1000配件板", 32, 2, 250, 70)
    else
        lcd.drawGtfontUtf8("AirFONTS_1000配件板", 32, 250, 70)
    end

    -- 设置背景色为白色，文字的前景色为红色
    lcd.setColor(0xFFFF, 0xF800)
    if font_demo_state.use_gray then
        lcd.drawGtfontUtf8Gray("支持10到192号的黑体字体", 32, 2, 228, 122)
    else
        lcd.drawGtfontUtf8("支持10到192号的黑体字体", 32, 228, 122)
    end

    -- 设置背景色为白色，文字的前景色为绿色
    lcd.setColor(0xFFFF, 0x07E0)
    if font_demo_state.use_gray then
        lcd.drawGtfontUtf8Gray("支持GBK中文和ASCII码字符集", 32, 2, 188, 174)
    else
        lcd.drawGtfontUtf8("支持GBK中文和ASCII码字符集", 32, 188, 174)
    end

    -- 设置背景色为白色，文字的前景色为蓝色
    lcd.setColor(0xFFFF, 0x001F)
    if font_demo_state.use_gray then
        lcd.drawGtfontUtf8Gray("支持灰度显示，字体边缘更平滑", 32, 2, 190, 226)
    else
        lcd.drawGtfontUtf8("支持灰度显示，字体边缘更平滑", 32, 190, 226)
    end

    -- 倒计时
    lcd.setColor(0xFFFF, 0x0000)
    if font_demo_state.use_gray then
        lcd.drawGtfontUtf8Gray("倒计时 ： " .. font_demo_state.countdown, 24, 2, 340, 278)
    else
        lcd.drawGtfontUtf8("倒计时 ： " .. font_demo_state.countdown, 24, 340, 278)
    end
    
    return false
end

--[[
绘制字体大小变化阶段
@local
@return boolean 是否完成所有阶段
]]
local function draw_font_size_phase()
    local _, current_time = mcu.ticks2(1)
    
    if current_time - font_demo_state.last_update > font_demo_state.font_update_interval then
        font_demo_state.current_size = font_demo_state.current_size + 1
        font_demo_state.last_update = current_time
    end
    
    -- 根据颜色阶段设置颜色
    if font_demo_state.color_phase == 1 then
        lcd.setColor(0xFFFF, 0x0000) -- 黑色
    elseif font_demo_state.color_phase == 2 then
        lcd.setColor(0xFFFF, 0xF800) -- 红色
    elseif font_demo_state.color_phase == 3 then
        lcd.setColor(0xFFFF, 0x07E0) -- 绿色
    else
        lcd.setColor(0xFFFF, 0x001F) -- 蓝色
    end
    
    -- 根据颜色阶段和字体大小显示不同内容
    if font_demo_state.color_phase == 1 then
        if font_demo_state.current_size <= 64 then
            if font_demo_state.use_gray then
                lcd.drawGtfontUtf8Gray(font_demo_state.current_size .. "号：合宙AirFONTS_1000", 
                                      font_demo_state.current_size, 4, 10, 100)
            else
                lcd.drawGtfontUtf8(font_demo_state.current_size .. "号：合宙AirFONTS_1000", 
                                  font_demo_state.current_size, 10, 100)
            end
        else
            font_demo_state.color_phase = 2
            font_demo_state.current_size = 65
        end
    elseif font_demo_state.color_phase == 2 then
        if font_demo_state.current_size <= 96 then
            if font_demo_state.use_gray then
                lcd.drawGtfontUtf8Gray(font_demo_state.current_size .. "号", 
                                      font_demo_state.current_size, 4, 10, 100)
                lcd.drawGtfontUtf8Gray("AirFONTS_1000", 
                                      font_demo_state.current_size, 4, 10, 100 + font_demo_state.current_size + 5)
            else
                lcd.drawGtfontUtf8(font_demo_state.current_size .. "号", 
                                  font_demo_state.current_size, 10, 100)
                lcd.drawGtfontUtf8("AirFONTS_1000", 
                                  font_demo_state.current_size, 10, 100 + font_demo_state.current_size + 5)
            end
        else
            font_demo_state.color_phase = 3
            font_demo_state.current_size = 97
        end
    elseif font_demo_state.color_phase == 3 then
        if font_demo_state.current_size <= 128 then
            if font_demo_state.use_gray then
                lcd.drawGtfontUtf8Gray(font_demo_state.current_size .. "号", 
                                      font_demo_state.current_size, 4, 210, 50)
                lcd.drawGtfontUtf8Gray("合宙", 
                                      font_demo_state.current_size, 4, 210, 50 + font_demo_state.current_size + 5)
            else
                lcd.drawGtfontUtf8(font_demo_state.current_size .. "号", 
                                  font_demo_state.current_size, 210, 50)
                lcd.drawGtfontUtf8("合宙", 
                                  font_demo_state.current_size, 210, 50 + font_demo_state.current_size + 5)
            end
        else
            font_demo_state.color_phase = 4
            font_demo_state.current_size = 129
        end
    else
        if font_demo_state.current_size <= 192 then
            -- 矢量字体大小目前不能到180号，常规字体可到192号
            -- if font_demo_state.use_gray then
            --     lcd.drawGtfontUtf8Gray(font_demo_state.current_size .. "号", 
            --                           font_demo_state.current_size, 4, 10, 50)
            --     lcd.drawGtfontUtf8Gray("合宙", 
            --                           font_demo_state.current_size, 4, 10, 50 + font_demo_state.current_size + 5)
            -- else
                lcd.drawGtfontUtf8(font_demo_state.current_size .. "号", 
                                  font_demo_state.current_size, 210, 50)
                lcd.drawGtfontUtf8("合宙", 
                                  font_demo_state.current_size, 210, 50 + font_demo_state.current_size + 5)
            -- end
        else
            -- 所有阶段完成，重置
            font_demo_state.demo_phase = 1
            font_demo_state.countdown = 5
            font_demo_state.color_phase = 1
            font_demo_state.current_size = 16
            return true
        end
    end
    
    return false
end

--[[
绘制字体演示内容
@local
@return nil
]]
local function draw_font_demo()
    -- 根据演示阶段调用不同的绘制函数
    if font_demo_state.demo_phase == 1 then
        draw_countdown_phase()
    else
        draw_font_size_phase()
    end
end

--[[
绘制GTFont演示页面；

@api gtfont_page.draw()
@summary 绘制GTFont演示页面的所有UI元素和字体演示内容
@return nil
]]
function gtfont_page.draw()
    lcd.clear()
    -- 绘制按钮区域
    draw_back_button()
    draw_switch_button()

    -- 绘制字体演示内容
    draw_font_demo()

    lcd.flush()
end

--[[
处理GTFont页面触摸事件；

@api gtfont_page.handle_touch(x, y, switch_page)
@number x 触摸点X坐标，范围0-799
@number y 触摸点Y坐标，范围0-479
@function switch_page 页面切换回调函数
@return boolean 事件处理成功返回true，否则返回false
]]
function gtfont_page.handle_touch(x, y, switch_page)
    -- 检查返回按钮
    if x >= back_button.x1 and x <= back_button.x2 and
        y >= back_button.y1 and y <= back_button.y2 then
        switch_page("home")
        return true
    end

    -- 检查切换按钮
    if x >= switch_button.x1 and x <= switch_button.x2 and
        y >= switch_button.y1 and y <= switch_button.y2 then
        font_demo_state.use_gray = not font_demo_state.use_gray
        return true
    end

    return false
end

--[[
页面进入时重置状态；

@api gtfont_page.on_enter()
@summary 重置字体演示状态到初始值
@return nil
]]
function gtfont_page.on_enter()
    font_demo_state.use_gray = true -- 默认灰度模式
    font_demo_state.demo_phase = 1
    font_demo_state.countdown = 18
    font_demo_state.current_size = 16
    font_demo_state.color_phase = 1
    local _, ms_l = mcu.ticks2(1)
    font_demo_state.last_update = ms_l
    frame_time = 20 -- 进入时改成20ms刷新一次
end


--[[
页面离开时恢复系统刷新率；

@api gtfont_page.on_leave()
@summary 恢复刷新率
@return nil
]]
function gtfont_page.on_leave()
    -- 恢复恢复20S刷新一次
    frame_time = 20*1000
end

return gtfont_page