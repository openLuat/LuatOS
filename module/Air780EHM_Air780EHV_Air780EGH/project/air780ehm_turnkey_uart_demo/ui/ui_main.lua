--[[
@module  ui_main
@summary UI主程序，管理页面切换（独立版本）
@version 1.0
@date    2026.03.17
]]

-- 加载页面模块
require "home_page"
require "uart_page"

-- 当前页面与栈
local current_page = nil
local page_stack = {}

-- SIM卡状态标志
sim_present = false

-- 页面映射表
local pages = {
    home = "home_page",
    uart = "uart_page",
}

-- 显示指定页面
local function show_page(page_name, params)
    log.info("ui_main", "【页面切换】显示页面:" .. page_name)

    if not params or not params.from_back then
        if current_page then
            log.info("ui_main", "【页面切换】保存当前页面到栈:" .. (current_page.name or "nil"))
            table.insert(page_stack, {
                name = current_page.name,
                instance = current_page.instance
            })
        end
    end

    if current_page and current_page.instance.cleanup then
        log.info("ui_main", "【页面切换】清理当前页面:" .. (current_page.name or "nil"))
        current_page.instance.cleanup()
    end

    local module_name = pages[page_name]
    if not module_name then
        log.error("ui_main", "页面不存在:", page_name)
        return false
    end

    log.info("ui_main", "【页面切换】加载页面模块:" .. module_name)
    local page_module = require(module_name)
    if page_module.init then
        log.info("ui_main", "【页面切换】初始化页面:" .. page_name)
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
    log.info("ui_main", "【页面返回】用户点击返回按钮，栈深度:" .. #page_stack)
    if #page_stack > 0 then
        local prev_page = table.remove(page_stack)
        log.info("ui_main", "【页面返回】返回到页面:" .. (prev_page.name or "nil"))
        if prev_page.instance and prev_page.instance.show then
            prev_page.instance.show()
            current_page = prev_page
        else
            return show_page(prev_page.name, { from_back = true })
        end
    else
        log.info("ui_main", "【页面返回】页面栈为空，返回主页")
        return show_page("home", { from_back = true })
    end
end

-- 主任务
local function ui_main_task()
    log.info("ui_main", "【UI主任务】UI主任务已启动")

    log.info("ui_main", "【UI主任务】初始化LCD驱动...")
    lcd_drv.init()

    log.info("ui_main", "【UI主任务】初始化触摸驱动...")
    tp_drv.init()

    -- 启动主页
    log.info("ui_main", "【UI主任务】启动主页...")
    show_page("home")

    -- 开启背光引脚供电
    log.info("ui_main", "【UI主任务】开启背光引脚供电(GPIO17)")
    gpio.setup(17, 0)
    log.info("ui_main", "【UI主任务】UI主任务初始化完成")
end

-- 全局导出
_G.show_page = show_page
_G.go_back = go_back

sys.taskInit(ui_main_task)
log.info("ui_main", "【UI主任务】UI主任务已启动")
