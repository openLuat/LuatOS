--[[
@module  ui_main
@summary UI主程序，负责页面管理和主循环
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件管理所有UI页面，包括主页和各个演示页面。
]]

require("home_page")
require("label_page")
require("button_page")
require("container_page")
require("bar_page")
require("switch_page")
require("dropdown_page")
require("table_page")
require("input_page")
require("msgbox_page")
require("image_page")
require("tabview_page")
require("win_page")
require("switch_page_demo")
require("hzfont_page")
require("game_page")
require("all_component_page")

-- 当前显示的页面
local current_page = nil
local page_stack = {} -- 页面，用于返回功能
local frame_time = 20 -- 主循环刷新间隔，单位ms


-- 页面定义
local pages = {
    home = "home_page",                    -- 主页
    label = "label_page",                  -- 标签演示
    button = "button_page",                -- 按钮演示
    container = "container_page",          -- 容器演示
    bar = "bar_page",                      -- 进度条演示
    switch = "switch_page",                -- 开关演示
    dropdown = "dropdown_page",            -- 下拉框演示
    table = "table_page",                  -- 表格演示
    input = "input_page",                  -- 输入框演示
    msgbox = "msgbox_page",                -- 消息框演示
    image = "image_page",                  -- 图片演示
    tabview = "tabview_page",              -- 选项卡演示
    win = "win_page",                      -- 窗口演示
    switch_page_demo = "switch_page_demo", -- 页面切换演示
    hzfont = "hzfont_page",                -- 矢量字体演示
    game = "game_page",                    -- 游戏演示
    all_component = "all_component_page",  -- 所有组件演示
}

-- 显示指定页面
local function show_page(page_name, params)
    -- 保存当前页面
    if not params or not params.from_back then
        if current_page then
            table.insert(page_stack, {
                name = current_page.name,
                instance = current_page.instance
            })
        end
    end

    -- 清理当前页面
    if current_page and current_page.instance.cleanup then
        current_page.instance.cleanup()
    end

    -- 加载新页面
    local module_name = pages[page_name]
    if not module_name then
        log.error("ui_main", "页面不存在:", page_name)
        return false
    end

    local page_module = require(module_name)

    -- 初始化页面
    if page_module.init then
        page_module.init(params)
    end

    -- 更新当前页面信息
    current_page = {
        name = page_name,
        module = module_name,
        instance = page_module
    }

    log.info("ui_main", "切换到页面:", page_name)
    return true
end

-- 返回上一个页面
local function go_back()
    if #page_stack > 0 then
        local prev_page = table.remove(page_stack)
        if prev_page.instance and prev_page.instance.show then
            prev_page.instance.show()
            current_page = prev_page
            log.info("ui_main", "返回页面:", prev_page.name)
            return true
        else
            return show_page(prev_page.name, { from_back = true })
        end
    else
        return show_page("home", { from_back = true })
    end
end

-- 主任务函数
local function ui_main_task()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 显示主页
    show_page("home")

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(frame_time)
    end
end

-- 全局函数，方便页面调用
_G.show_page = show_page
_G.go_back = go_back

-- 启动UI主任务
sys.taskInit(ui_main_task)