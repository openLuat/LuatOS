--[[
@module  ui_main
@summary 用户界面主控模块，负责页面管理和事件分发
@version 1.0
@date    2025.12.8
@author  江访
@usage
本模块为用户界面主控模块，核心业务逻辑为：
1、管理页面切换和事件分发，支持主页、LCD演示页和自定义字体演示页；
2、处理按键事件，分发到对应页面的处理函数；
3、控制界面刷新频率，支持不同页面的不同刷新率需求；
4、加载和切换自定义字体文件；

注意：当前仅支持自定义点阵字体

本文件的对外接口：通过sys.taskInit(ui_main)启动UI主循环
]]

-- 加载子页面
local home_page = require "home_page"
local lcd_page = require "lcd_page"
local customer_font_page = require "customer_font_page"

-- 当前页面状态
local current_page = "home"
local last_page = ""
frame_time = 20 * 1000 -- 超时刷新时间，进入刷新率要求高的页面可以更此变量，退出再更改回来

--[[
切换页面；
@api switch_page(new_page)
@summary 执行页面切换操作
@string new_page 目标页面名称
@valid_values "home", "lcd", "customer_font"
@return nil
]]
local function switch_page(new_page)
    log.info("switch_page", "从", current_page, "切换到", new_page)
    
    -- 调用旧页面的退出函数
    if current_page == "home" and home_page.on_leave then
        home_page.on_leave()
    elseif current_page == "lcd" and lcd_page.on_leave then
        lcd_page.on_leave()
    elseif current_page == "customer_font" and customer_font_page.on_leave then
        customer_font_page.on_leave()
    end

    last_page = current_page
    current_page = new_page

    -- 调用新页面的进入函数
    if new_page == "home" and home_page.on_enter then
        home_page.on_enter()
    elseif new_page == "lcd" and lcd_page.on_enter then
        lcd_page.on_enter()
    elseif new_page == "customer_font" and customer_font_page.on_enter then
        customer_font_page.on_enter()
    end

    log.info("ui_main", "已切换到页面:", current_page)
end

--[[
处理按键事件；
@api handle_key_event(key_event)
@summary 处理按键事件并分发到对应页面
@string key_event 按键事件类型
@valid_values "boot_up", "pwr_up"
@return bool 事件处理成功返回true，否则返回false
]]
local function handle_key_event(key_event)
    log.info("按键事件", "event:", key_event, "当前页面:", current_page)
    
    -- 只在按键释放时处理
    if key_event == "boot_up" then
        -- BOOT键：在主页作为方向键
        if current_page == "home" then
            return home_page.handle_key("next", switch_page)
        end
        -- 其他页面BOOT键无功能
        return false
    elseif key_event == "pwr_up" then
        -- PWR键：确认/返回功能
        if current_page == "home" then
            return home_page.handle_key("confirm", switch_page)
        elseif current_page == "lcd" then
            if lcd_page.handle_key then
                return lcd_page.handle_key("pwr_up", switch_page)
            end
        elseif current_page == "customer_font" then
            if customer_font_page.handle_key then
                return customer_font_page.handle_key("pwr_up", switch_page)
            end
        end
    end
    
    return false
end

--[[
用户界面主任务；
@api ui_main()
@summary 初始化显示和按键驱动，启动UI主循环
@return nil
]]
local function ui_main()
    if not lcd_drv.init() then
        log.error("ui_main", "显示初始化失败")
        return
    end

    if not key_drv.init() then
        log.error("ui_main", "按键驱动初始化失败")
        return
    end

    -- 使用自定义字体（12号）
    lcd.setFontFile("/luadb/customer_font_12.bin")

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
        elseif current_page == "customer_font" then
            customer_font_page.draw()
        end

        lcd.flush()

        -- 等待按键事件
        local result, key_event = sys.waitUntil("KEY_EVENT", frame_time)
        if result then
            handle_key_event(key_event)
        end
    end
end

sys.taskInit(ui_main)