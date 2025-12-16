--[[
@module  ui_main
@summary exEasyUI主程序模块
@version 1.0
@date    2025.12.10
@author  江访
@usage
本文件为exEasyUI主程序模块，核心业务逻辑为：
1、初始化UI主题和窗口系统；
2、注册所有页面的可点击区域回调函数；
3、包装窗口方法以捕获页面切换事件；
4、订阅按键事件并分发到按键处理器；
5、启动UI渲染主循环，维持界面刷新；

本文件的对外接口有0个：
1、require加载后自动启动UI主任务；
]]

local home_page = require("home_page")
local key_handler = require("key_handler")

-- 页面名称常量
local PAGE_NAMES = {
    HOME = "home",
    COMPONENT = "component",
    DEFAULT_FONT = "default_font",
}

-- 当前页面
local current_page = nil

-- 处理按键事件
local function handle_key_event(event_type)
    if event_type == "boot_down" then
        key_handler.next_area()
    elseif event_type == "pwr_down" then
        key_handler.simulate_click()
    end
end

-- 主页区域回调函数
local function home_page_callback()
    key_handler.clear_areas()
    key_handler.add_area(20, 100, 280, 50) -- 组件按钮
    key_handler.add_area(20, 170, 280, 50) -- 默认字体按钮
    log.info("ui_main", "已注册主页区域，共4个区域")
end

-- 组件页面区域回调函数
local function component_page_callback()
    key_handler.clear_areas()
    key_handler.add_area(20, 20, 60, 30)   -- 返回按钮
    key_handler.add_area(210, 100, 70, 26) -- +10%按钮
    key_handler.add_area(20, 170, 85, 30)  -- 复选框A
    key_handler.add_area(120, 170, 85, 30) -- 复选框B
    key_handler.add_area(20, 430, 80, 30)  -- 普通按钮
    key_handler.add_area(110, 430, 80, 30) -- 蓝色按钮
    key_handler.add_area(200, 430, 64, 30) -- 图片按钮
    log.info("ui_main", "已注册组件页面区域，共7个区域")
end

-- 默认字体页面区域回调函数
local function default_font_page_callback()
    key_handler.clear_areas()
    key_handler.add_area(20, 20, 60, 30) -- 返回
    log.info("ui_main", "已注册默认字体页面区域，共1个区域")
end



-- 注册所有页面的回调函数
local function register_all_pages()
    key_handler.register_page(PAGE_NAMES.HOME, home_page_callback)
    key_handler.register_page(PAGE_NAMES.COMPONENT, component_page_callback)
    key_handler.register_page(PAGE_NAMES.DEFAULT_FONT, default_font_page_callback)
end

-- 页面切换处理
local function handle_page_change(page_name)
    if not page_name then
        page_name = PAGE_NAMES.HOME
    end

    if page_name ~= current_page then
        current_page = page_name
        key_handler.switch_to_page(page_name)
    end
end

-- 页面切换任务函数
local function show_subpage_task(page_name)
    handle_page_change(page_name)
end

local function back_task()
    handle_page_change(PAGE_NAMES.HOME)
end

-- 包装的show_subpage方法
local function wrapped_show_subpage(self, page_name)
    -- 调用原始方法
    local original_show_subpage = getmetatable(self).original_show_subpage
    original_show_subpage(self, page_name)

    if page_name then
        sys.taskInit(show_subpage_task, page_name)
    end
end

-- 包装的back方法
local function wrapped_back(self)
    -- 调用原始方法
    local original_back = getmetatable(self).original_back
    original_back(self)

    sys.taskInit(back_task)
end

-- 包装窗口方法
local function wrap_window_methods()
    local test_win = ui.window({})
    local window_meta = getmetatable(test_win)

    -- 保存原始方法
    window_meta.original_show_subpage = window_meta.show_subpage
    window_meta.original_back = window_meta.back

    -- 替换为包装的方法
    window_meta.show_subpage = wrapped_show_subpage
    window_meta.back = wrapped_back
end

-- 启动UI主任务
local function ui_main()
    -- 初始化UI主题
    ui.sw_init({ theme = "light" })

    -- 包装窗口方法
    wrap_window_methods()
    register_all_pages()

    -- 创建主页
    home_page.create()

    -- 确保光标显示
    key_handler.switch_to_page(PAGE_NAMES.HOME)

    -- 订阅按键事件
    sys.subscribe("KEY_EVENT", handle_key_event)

    -- 主渲染循环
    while true do
        ui.refresh()
        sys.wait(30)
    end
end

sys.taskInit(ui_main)
