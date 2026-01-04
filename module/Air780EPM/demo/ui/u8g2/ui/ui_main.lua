--[[
@module  ui_main
@summary U8G2主程序模块 - 128x64屏幕
@version 1.0
@date    2025.12.23
@author  江访
@usage
本文件为U8G2图形界面的主控模块，核心业务逻辑为：
1、管理三个页面：主页、组件演示页、内置字体页；
2、处理按键事件并分发给当前页面；
3、控制页面切换逻辑，调用页面的进入/离开回调函数；
4、实现主渲染循环，定期更新屏幕显示；

本文件的对外接口有2个：
1、switch_page(new_page)：页面切换接口；
2、handle_key_event(key_event)：按键事件处理入口；
]]

-- 加载页面
local home_page = require("home_page")
local component_page = require("component_page")
local default_font_page = require("default_font_page")

-- 超时更新画面时间，默认60秒
frame_time = 60 * 1000

-- 页面管理
local PAGE_NAMES = {
    HOME = "home",
    COMPONENT = "component",
    DEFAULT_FONT = "default_font"
}

-- 当前页面
local current_page = PAGE_NAMES.HOME

--[[
@api handle_key_event(key_event)
@summary 处理按键事件
@param string key_event 按键事件类型，可选值："boot_up"、"boot_down"、"pwr_up"、"pwr_down"
@return bool 是否已处理该按键事件
@usage
-- 在主循环中调用
handle_key_event("boot_up")
]]
-- 按键处理函数
local function handle_key_event(key_event)
    log.info("Key event", "event:", key_event, "Current page:", current_page)

    -- 按键抬起生效
    if key_event == "boot_up" then
        -- BOOT键抬起：切换到下一个选项
        if current_page == PAGE_NAMES.HOME then
            return home_page.handle_key("next")
        elseif current_page == PAGE_NAMES.COMPONENT then
            return component_page.handle_key("next")
        elseif current_page == PAGE_NAMES.DEFAULT_FONT then
            return default_font_page.handle_key("next")
        end
        return false
    elseif key_event == "pwr_up" then
        -- PWR键抬起：确认/返回
        if current_page == PAGE_NAMES.HOME then
            return home_page.handle_key("confirm")
        elseif current_page == PAGE_NAMES.COMPONENT then
            return component_page.handle_key("confirm")
        elseif current_page == PAGE_NAMES.DEFAULT_FONT then
            return default_font_page.handle_key("confirm")
        end
    end
    return false
end

--[[
@api switch_page(new_page)
@summary 切换当前显示的页面
@param string new_page 要切换到的页面名称，可选值："home"、"component"、"default_font"
@return 无返回值
@usage
-- 在页面处理函数中调用
switch_page("home")
]]
-- 页面切换函数（供其他页面调用）
function switch_page(new_page)
    log.info("switch_page", "From", current_page, "to", new_page)

    -- 调用旧页面的离开函数
    if current_page == PAGE_NAMES.HOME and home_page.on_leave then
        home_page.on_leave()
    elseif current_page == PAGE_NAMES.COMPONENT and component_page.on_leave then
        component_page.on_leave()
    elseif current_page == PAGE_NAMES.DEFAULT_FONT and default_font_page.on_leave then
        default_font_page.on_leave()
    end

    current_page = new_page

    -- 调用新页面的进入函数
    if new_page == PAGE_NAMES.HOME and home_page.on_enter then
        home_page.on_enter()
    elseif new_page == PAGE_NAMES.COMPONENT and component_page.on_enter then
        component_page.on_enter()
    elseif new_page == PAGE_NAMES.DEFAULT_FONT and default_font_page.on_enter then
        default_font_page.on_enter()
    end

    log.info("ui_main", "Switched to page:", current_page)
end

-- 主UI任务
local function ui_main()

    -- 预留1S给开机信息显示
    sys.wait(1000)
    log.info("ui_main", "Start UI main loop")

    -- 初始化主页
    home_page.on_enter()

    -- 主渲染循环
    while true do
        -- 设置默认字体
        u8g2.SetFont(u8g2.font_6x10) -- 使用英文字体
        -- 清空缓冲区
        u8g2.ClearBuffer()

        -- 根据当前页面绘制内容
        if current_page == PAGE_NAMES.HOME then
            home_page.draw()
        elseif current_page == PAGE_NAMES.COMPONENT then
            component_page.draw()
        elseif current_page == PAGE_NAMES.DEFAULT_FONT then
            default_font_page.draw()
        end

        -- 刷新显示
        u8g2.SendBuffer()

        -- 等待按键事件
        local result, key_event = sys.waitUntil("KEY_EVENT", frame_time)
        if result then
            handle_key_event(key_event)
        end
    end
end

-- 启动UI任务
sys.taskInit(ui_main)