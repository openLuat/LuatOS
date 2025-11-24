--[[
@module  ui_main
@summary 用户界面主控模块，负责页面管理和事件分发
@version 1.0
@date    2025.11.20
@author  江访
@usage
本模块为核心UI控制模块，主要功能包括：
1、初始化LCD显示和触摸面板驱动；
2、管理多个页面之间的切换逻辑；
3、分发触摸事件到各个页面处理；
4、维护页面状态和生命周期管理；

对外接口：
1、ui_main()：主UI任务入口函数
2、switch_page()：页面切换函数
3、handle_touch_event()：触摸事件处理函数
]]


-- 加载子页面
local home_page = require "home_page"
local lcd_page = require "lcd_page"
local gtfont_page = require "gtfont_page"
local customer_font_page = require "customer_font_page"

-- 当前页面状态
local current_page = "home"
local last_page = ""
frame_time = 20*1000

--[[
切换页面；

@api switch_page(new_page)
@string new_page 目标页面名称
@valid_values "home", "lcd", "gtfont", "customer_font_page"
@return nil

@usage
-- 切换到LCD演示页面
switch_page("lcd")
]]
local function switch_page(new_page)
    -- 调用旧页面的退出函数（如果存在）
    if current_page == "home" and home_page.on_leave then
        home_page.on_leave()
    elseif current_page == "lcd" and lcd_page.on_leave then
        lcd_page.on_leave()
    elseif current_page == "gtfont" and gtfont_page.on_leave then
        gtfont_page.on_leave()
    elseif current_page == "customer_font_page" and customer_font_page.on_leave then
        customer_font_page.on_leave()
    end

    last_page = current_page
    current_page = new_page

    -- 调用新页面的进入函数（如果存在）
    if new_page == "home" and home_page.on_enter then
        home_page.on_enter()
    elseif new_page == "lcd" and lcd_page.on_enter then
        lcd_page.on_enter()
    elseif new_page == "gtfont" and gtfont_page.on_enter then
        gtfont_page.on_enter()
    elseif new_page == "customer_font_page" and customer_font_page.on_enter then
        customer_font_page.on_enter()
    end

    log.info("ui_main", "切换到页面:", current_page)
end

--[[
处理触摸事件；

@api handle_touch_event(event, x, y)
@number event 触摸事件类型
@valid_values tp.EVENT_DOWN, tp.EVENT_MOVE, tp.EVENT_UP
@number x 触摸点X坐标，范围0-319
@number y 触摸点Y坐标，范围0-479
@return boolean 事件处理成功返回true，否则返回false
]]
-- 处理触摸事件
local function handle_touch_event(event, x, y)
    log.info("触摸事件", "event:", event, "x:", x, "y:", y)

    if event then -- 只在抬起时处理点击
        if current_page == "home" then
            return home_page.handle_touch(x, y, switch_page)
        elseif current_page == "lcd" then
            return lcd_page.handle_touch(x, y, switch_page)
        elseif current_page == "gtfont" then
            return gtfont_page.handle_touch(x, y, switch_page)
        elseif current_page == "customer_font_page" then
            return gtfont_page.handle_touch(x, y, switch_page)
        end
    end
    return false
end

--[[
用户界面主任务；

@api ui_main()
@summary 初始化显示和触摸驱动，启动UI主循环
@return nil
]]
local function ui_main()
    if not lcd_drv.init() then
        log.error("ui_main", "显示初始化失败")
        return
    end

    if not tp_drv.init() then
        log.error("ui_main", "触摸初始化失败")
        return
    end

    -- 默认使用系统自带的12号中文字体
    lcd.setFont(lcd.font_opposansm12_chinese)

    -- 调用主页的进入函数
    if home_page.on_enter then
        home_page.on_enter()
    end

    while true do
        -- 根据当前页面绘制内容
        if current_page == "home" then
            home_page.draw()
        elseif current_page == "lcd" then
            lcd_page.draw()
        elseif current_page == "gtfont" then
            gtfont_page.draw()
        elseif current_page == "customer_font_page" then
            customer_font_page.draw()
        end

        lcd.flush()


        -- 等待触摸事件
        local result, event, x, y = sys.waitUntil("BASE_TOUCH_EVENT",frame_time)
        if result then
            handle_touch_event(event, x, y)
        end
    end
end


sys.taskInit(ui_main)
