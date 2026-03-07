--[[
@module  ui_main
@summary UI主程序，管理页面切换
@version 1.0
@date    2026.03.03
]]

-- 加载页面模块
require "home_page"
require "all_app_page"
require "call_page"
require "all_app_page"
require "camera_page"
require "network_select_page"
require "gps_page"
require "sensor_page"
require "iot_account_page"
require "bluetooth_page"
require "uart_page"
require "record_page"
require "tts_page"
require "apn_page"
require "ethernet_page"
require "wifi_page"

-- 当前页面与栈
local current_page = nil
local page_stack = {}

-- SIM卡状态标志及订阅ID，全部UI页面可以使用，判断当前联网情况
sim_present = false
aircloud_qr = nil

-- 页面映射表
local pages = {
    home = "home_page",
    all_app = "all_app_page",
    call = "call_page",
    camera = "camera_page",
    network_select = "network_select_page",
    gps = "gps_page",
    sensor = "sensor_page",
    iot_account = "iot_account_page",
    bluetooth = "bluetooth_page",
    uart = "uart_page",
    record = "record_page",
    tts = "tts_page",
    apn = "apn_page",
    ethernet = "ethernet_page",
    wifi = "wifi_page",
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

    -- 开启背光引脚供电
    gpio.setup(1, 1)
end

-- 全局导出
_G.show_page = show_page
_G.go_back = go_back

sys.taskInit(ui_main_task)
