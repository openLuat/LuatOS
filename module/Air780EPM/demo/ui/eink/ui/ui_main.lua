--[[
@module  ui_main
@summary eink用户界面主控模块，负责页面管理和事件分发
@version 1.0
@date    2025.12.18
@author  江访  
本模块为eink用户界面主控模块，主要功能包括：
1、管理页面切换和事件分发；
2、处理按键事件并调用对应页面的处理函数；
3、协调各页面之间的状态转移；
4、控制界面刷新频率；

对外接口：
1、ui_main()：用户界面主任务，初始化显示和按键驱动，启动UI主循环
]] 

-- 加载子页面
local home_page = require "home_page"
local eink_page = require "eink_page"
local time_page = require "time_page"

-- 当前页面状态
local current_page = "home"
local last_page = ""

--[[
切换页面；
从当前页面切换到目标页面；

@api switch_page(new_page)
@summary 执行页面切换操作
@string new_page 目标页面名称
@valid_values "home", "eink_demo", "time_demo"
@return nil

@usage
-- 切换到主页
switch_page("home")

-- 切换到eink演示页面
switch_page("eink_demo")

-- 切换到时间显示页面
switch_page("time_demo")
]] 
local function switch_page(new_page)
    log.info("switch_page", "从", current_page, "切换到", new_page)
    
    -- 调用旧页面的退出函数
    if current_page == "home" and home_page.on_leave then
        home_page.on_leave()
    elseif current_page == "eink_demo" and eink_page.on_leave then
        eink_page.on_leave()
    elseif current_page == "time_demo" and time_page.on_leave then
        time_page.on_leave()
    end

    last_page = current_page
    current_page = new_page

    -- 调用新页面的进入函数
    if new_page == "home" and home_page.on_enter then
        home_page.on_enter()
    elseif new_page == "eink_demo" and eink_page.on_enter then
        eink_page.on_enter()
    elseif new_page == "time_demo" and time_page.on_enter then
        time_page.on_enter()
    end

    log.info("ui_main", "已切换到页面:", current_page)
end

--[[
处理按键事件；
根据按键类型和当前页面调用对应的处理函数；

@api handle_key_event(key_event)
@summary 处理按键事件并分发到对应页面
@string key_event 按键事件类型
@valid_values "boot_up", "pwr_up"
@return bool 事件处理成功返回true，否则返回false

@usage
-- 在ui_main任务中调用
local handled = handle_key_event("boot_up")
]] 
local function handle_key_event(key_event)
    log.info("按键事件", "event:", key_event, "当前页面:", current_page)
    
    if key_event == "boot_up" then
        -- BOOT键：在主页作为方向键，在时间页面切换格式
        if current_page == "home" then
            -- 主页：切换选项
            return home_page.handle_key("boot_up", switch_page)
        elseif current_page == "time_demo" then
            -- 时间页面：切换时间格式
            if time_page.handle_key then
                return time_page.handle_key("boot_up", switch_page)
            end
        end
        -- 其他页面BOOT键无功能
        return false
    elseif key_event == "pwr_up" then
        -- PWR键：确认/返回功能
        if current_page == "home" then
            return home_page.handle_key("confirm", switch_page)
        elseif current_page == "eink_demo" then
            -- eink演示页面：返回首页
            if eink_page.handle_key then
                return eink_page.handle_key("pwr_up", switch_page)
            end
        elseif current_page == "time_demo" then
            -- 时间页面：返回首页
            if time_page.handle_key then
                return time_page.handle_key("pwr_up", switch_page)
            end
        end
    end
    
    return false
end

--[[
用户界面主任务；
初始化显示和按键驱动，启动UI主循环；

@api ui_main()
@summary 初始化显示和按键驱动，启动UI主循环
@return nil

@usage
-- 在主程序中通过sys.taskInit调用
sys.taskInit(ui_main)
]] 
local function ui_main()

    -- 调用主页的进入函数
    if home_page.on_enter then
        home_page.on_enter()
    end

    while true do
        -- 根据当前页面绘制内容
        if current_page == "home" then
            home_page.draw()
        elseif current_page == "eink_demo" then
            eink_page.draw()
        elseif current_page == "time_demo" then
            time_page.draw()
        end

        local result, key_event = sys.waitUntil("KEY_EVENT")
        if result then
            -- 处理按键事件
            handle_key_event(key_event)
        else
            -- 超时：时间页面需要刷新显示
            if current_page == "time_demo" then
                if time_page.need_update then
                    time_page.draw()
                end
            end
        end
    end
end

sys.taskInit(ui_main)