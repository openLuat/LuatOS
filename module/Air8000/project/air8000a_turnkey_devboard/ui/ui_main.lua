--[[
@module  ui_main
@summary UI主程序，管理页面切换（仅含两个页面）
@version 1.0
@date    2026.03.03
]]

-- 只保留两个页面模块
require("home_page")
require("all_app_page")

-- 当前页面与栈
local current_page = nil
local page_stack = {}

-- SIM卡状态标志及订阅ID
sim_present = false

-- 页面映射表
local pages = {
    home = "home_page",
    all_app = "all_app_page",
}

-- 显示指定页面
local function show_page(page_name, params)
    if not params or not params.from_back then
        if current_page then
            table.insert(page_stack, {
                name = current_page.name,
                instance = current_page.instance
            })
        end
    end

    if current_page and current_page.instance.cleanup then
        current_page.instance.cleanup()
    end

    local module_name = pages[page_name]
    if not module_name then
        log.error("ui_main", "页面不存在:", page_name)
        return false
    end

    local page_module = require(module_name)
    if page_module.init then
        page_module.init(params)
    end

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
        else
            return show_page(prev_page.name, { from_back = true })
        end
    else
        return show_page("home", { from_back = true })
    end
end

-- 主任务
local function ui_main_task()
    lcd_drv.init()
    tp_drv.init()

    -- 启动主页
    show_page("home")

    -- 主循环（AirUI v1.0.3+ 无需手动刷新）
end

-- 全局导出
_G.show_page = show_page
_G.go_back = go_back

sys.taskInit(ui_main_task)