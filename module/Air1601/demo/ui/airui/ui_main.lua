--[[
@module  ui_main
@summary UI主程序，负责页面管理和主循环
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件管理所有UI页面，包括主页和各个演示页面。
]]

require("airui_home")
require("airui_label")
require("airui_button")
require("airui_container")
require("airui_bar")
require("airui_switch")
require("airui_dropdown")
require("airui_table")
require("airui_input")
require("airui_msgbox")
require("airui_image")
require("airui_tabview")
require("airui_win")
require("airui_switch_page")
require("airui_hzfont")
require("airui_game")
require("airui_all_component")

-- 当前显示的页面
local current_page = nil
local page_stack = {} -- 页面，用于返回功能
local frame_time = 50 -- 主循环刷新间隔，单位ms

local function meminfo_information()
    local total_lua, used_lua, max_used_lua = rtos.meminfo("lua")
    local total_sys, used_sys, max_used_sys = rtos.meminfo("sys")
    log.info("内存信息",
        "Lua - 总:", total_lua, "已用:", used_lua, "峰值:", max_used_lua,
        "系统 - 总:", total_sys, "已用:", used_sys, "峰值:", max_used_sys)
end

-- 页面定义
local pages = {
    home = "airui_home",                    -- 主页
    label = "airui_label",                  -- 标签演示
    button = "airui_button",                -- 按钮演示
    container = "airui_container",          -- 容器演示
    bar = "airui_bar",                      -- 进度条演示
    switch = "airui_switch",                -- 开关演示
    dropdown = "airui_dropdown",            -- 下拉框演示
    table = "airui_table",                  -- 表格演示
    input = "airui_input",                  -- 输入框演示
    msgbox = "airui_msgbox",                -- 消息框演示
    image = "airui_image",                  -- 图片演示
    tabview = "airui_tabview",              -- 选项卡演示
    win = "airui_win",                      -- 窗口演示
    airui_switch_page = "airui_switch_page", -- 页面切换演示
    hzfont = "airui_hzfont",                -- 矢量字体演示
    game = "airui_game",                    -- 游戏演示
    all_component = "airui_all_component",  -- 所有组件演示
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

    sys.timerLoopStart(meminfo_information, 5000)
    
    -- 加载字体
    airui.font_load({
        type = "hzfont",
        path = nil,
        size = 14,
        cache_size = 1024,
        antialias = 2,
    })

    -- 显示主页
    show_page("home")

--     -- 主循环
--     while true do
--         airui.refresh()
--         sys.wait(frame_time)
--     end
 end

-- 全局函数，方便页面调用
_G.show_page = show_page
_G.go_back = go_back

-- 启动UI主任务
sys.taskInit(ui_main_task)