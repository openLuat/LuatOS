--[[
@module  ui_main
@summary epd用户界面主控模块，负责页面管理和事件分发
@version 1.0
@date    2026.08.19
@author  江访
本模块为epd用户界面主控模块，主要功能包括：
1、管理页面切换和事件分发；
2、处理按键事件并调用对应页面的处理函数；
3、协调各页面之间的状态转移；
4、控制界面刷新频率；

对外接口：
1、ui_main()：用户界面主任务，初始化显示和按键驱动，启动UI主循环
]]

-- 加载子页面
local home_page = require "home_page"
local epd_page = require "epd_page"
local info_page = require "info_page"
local time_page = require "time_page"

-- 当前页面状态
local current_page = "home"
local last_page = ""

-- 上次PWR键事件时间（用于down/up事件去重）
local last_pwr_ticks = 0
-- 上次BOOT键事件时间（用于down/up事件去重）
local last_boot_ticks = 0
-- 按键轮询超时（毫秒），超时后检查页面是否需要自动刷新
local KEY_POLL_MS = 200

--[[
切换页面；
从当前页面切换到目标页面；

@api switch_page(new_page)
@summary 执行页面切换操作
@string new_page 目标页面名称
@valid_values "home", "epd_demo", "info_demo", "time_demo"
@return nil

@usage
-- 切换到主页
switch_page("home")

-- 切换到epd图形演示页面
switch_page("epd_demo")

-- 切换到动态信息页面
switch_page("info_demo")

-- 切换到时间显示页面
switch_page("time_demo")
]]
local function switch_page(new_page)
    log.info("switch_page", "从", current_page, "切换到", new_page)

    -- 调用旧页面的退出函数
    if current_page == "home" and home_page.on_leave then
        home_page.on_leave()
    elseif current_page == "epd_demo" and epd_page.on_leave then
        epd_page.on_leave()
    elseif current_page == "info_demo" and info_page.on_leave then
        info_page.on_leave()
    elseif current_page == "time_demo" and time_page.on_leave then
        time_page.on_leave()
    end

    last_page = current_page
    current_page = new_page

    -- 调用新页面的进入函数
    if new_page == "home" and home_page.on_enter then
        home_page.on_enter()
    elseif new_page == "epd_demo" and epd_page.on_enter then
        epd_page.on_enter()
    elseif new_page == "info_demo" and info_page.on_enter then
        info_page.on_enter()
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

    if key_event == "boot_up" or key_event == "boot_down" then
        -- BOOT键：按下(boot_down)和释放(boot_up)都触发
        -- 注意：部分平台BOOT键释放沿中断不稳定，只响应释放会漏按，
        --      因此按下和释放都按方向键处理，并做去重
        local now = mcu.ticks()
        if key_event == "boot_up" and (now - last_boot_ticks) < 500 then
            -- boot_up 紧跟 boot_down 到达，视为同一次按键，忽略
            return false
        end
        last_boot_ticks = now

        if current_page == "home" then
            -- 主页：切换选项
            return home_page.handle_key("boot_up", switch_page)
        elseif current_page == "info_demo" then
            -- 信息页面：刷新动态信息
            if info_page.handle_key then
                return info_page.handle_key("boot_up", switch_page)
            end
        end
        -- 其他页面BOOT键无功能
        return false
    elseif key_event == "pwr_up" or key_event == "pwr_down" then
        -- PWR键：确认/返回功能
        -- 注意：部分平台PWR键释放沿不触发中断，只有pwr_down事件，
        --      因此按下(pwr_down)和释放(pwr_up)都按确认处理；
        --      同一次按键可能先后产生down/up两个事件，需去重
        local now = mcu.ticks()
        if key_event == "pwr_up" and (now - last_pwr_ticks) < 1000 then
            -- pwr_up 紧跟 pwr_down 到达，视为同一次按键，忽略
            return false
        end
        last_pwr_ticks = now
        if current_page == "home" then
            return home_page.handle_key("confirm", switch_page)
        elseif current_page == "epd_demo" then
            -- epd演示页面：返回首页
            if epd_page.handle_key then
                return epd_page.handle_key("pwr_up", switch_page)
            end
        elseif current_page == "info_demo" then
            -- 信息页面：返回首页
            if info_page.handle_key then
                return info_page.handle_key("pwr_up", switch_page)
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

    -- 是否需要重绘当前页面（页面切换/按键触发时置true）
    local need_redraw = true

    while true do
        -- 需要重绘时，绘制当前页面
        if need_redraw then
            if current_page == "home" then
                home_page.draw()
            elseif current_page == "epd_demo" then
                epd_page.draw()
            elseif current_page == "info_demo" then
                info_page.draw()
            elseif current_page == "time_demo" then
                time_page.draw()
            end
            need_redraw = false
        end

        -- 等待按键事件，带超时以便周期检查页面自动刷新
        local result, key_event = sys.waitUntil("KEY_EVENT", KEY_POLL_MS)
        if result then
            -- 处理按键事件（页面内部可能调用switch_page，或置need_redraw）
            handle_key_event(key_event)
            -- 按键可能切换了选中项，需要重绘
            need_redraw = true
        else
            -- 超时：检查需要自动刷新的页面
            if current_page == "time_demo" then
                if time_page.need_update then
                    time_page.auto_update()
                end
            elseif current_page == "info_demo" then
                if info_page.need_update then
                    info_page.auto_update()
                end
            end
        end
    end
end

sys.taskInit(ui_main)
