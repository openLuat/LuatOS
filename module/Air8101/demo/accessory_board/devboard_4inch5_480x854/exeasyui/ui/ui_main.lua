--[[
@module ui_main
@summary exEasyUI主程序模块
@version 1.0
@date 2026.01.26
@author 江访
@usage
本文件为exEasyUI主程序模块，核心业务逻辑为：
1、初始化UI主题和窗口系统；
2、注册所有页面的可点击区域回调函数；
3、包装窗口方法以捕获页面切换事件；
4、订阅按键事件并分发到按键处理器；
5、启动UI渲染主循环，维持界面刷新；

本文件无对外接口，require加载后自动执行初始化；
]]

local home_page = require("home_page")
local key_handler = require("key_handler")

-- 页面名称常量
local PAGE_NAMES = {
    HOME = "home",
    COMPONENT = "component",
    DEFAULT_FONT = "default_font",
    HZFONT = "hzfont"
}

-- 当前页面
local current_page = nil

-- 处理按键事件
local function handle_key_event(event_type)
    if event_type == "key1_down" then
        key_handler.next_area()
    elseif event_type == "key2_down" then
        key_handler.simulate_click()
    end
end

-- 主页区域回调函数
local function home_page_callback()
    key_handler.clear_areas()
    key_handler.add_area(60, 180, 360, 60) -- 组件演示按钮
    key_handler.add_area(60, 280, 360, 60) -- 默认字体按钮
    key_handler.add_area(60, 380, 360, 60) -- HZFont按钮
    log.info("ui_main", "已注册主页区域，共3个区域")
end

-- 组件页面区域回调函数
local function component_page_callback()
    key_handler.clear_areas()
    key_handler.add_area(20, 30, 80, 50)    -- 返回按钮
    key_handler.add_area(380, 140, 70, 40)  -- +10%按钮
    key_handler.add_area(40, 250, 120, 40)  -- 复选框A
    key_handler.add_area(200, 250, 120, 40) -- 复选框B
    key_handler.add_area(180, 520, 120, 45) -- 下一张按钮
    key_handler.add_area(40, 670, 120, 55)  -- 普通按钮
    key_handler.add_area(180, 670, 120, 55) -- 蓝色按钮
    key_handler.add_area(320, 670, 120, 55) -- 图片按钮
    log.info("ui_main", "已注册组件页面区域，共8个区域")
end

-- 默认字体页面区域回调函数
local function default_font_page_callback()
    key_handler.clear_areas()
    key_handler.add_area(20, 25, 80, 50) -- 返回按钮
    log.info("ui_main", "已注册默认字体页面区域，共1个区域")
end

-- HZFont页面区域回调函数
local function hzfont_page_callback()
    key_handler.clear_areas()
    key_handler.add_area(20, 25, 80, 50)    -- 返回按钮
    key_handler.add_area(40, 200, 150, 55)  -- 增大字体按钮
    key_handler.add_area(210, 200, 150, 55) -- 减小字体按钮
    log.info("ui_main", "已注册HZFont页面区域，共3个区域")
end

-- 注册所有页面的回调函数
local function register_all_pages()
    key_handler.register_page(PAGE_NAMES.HOME, home_page_callback)
    key_handler.register_page(PAGE_NAMES.COMPONENT, component_page_callback)
    key_handler.register_page(PAGE_NAMES.DEFAULT_FONT, default_font_page_callback)
    key_handler.register_page(PAGE_NAMES.HZFONT, hzfont_page_callback)
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
end

sys.taskInit(ui_main)
