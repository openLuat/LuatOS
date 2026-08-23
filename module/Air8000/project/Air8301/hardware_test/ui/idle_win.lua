--[[
@module  idle_win
@summary 首页窗口模块，功能菜单网格，参考 AirUI demo home_win 风格
@version 1.1.0
@date    2026.08.04
@author  江访
@usage
首页以功能菜单网格展示12个功能入口，点击后通过发布 OPEN_XXX_WIN 消息跳转。
顶部显示产品名称和时间。
]]

local win_id = nil
local main_container, scroll_container, time_label
local current_time = "00:00"

-- 颜色常量
local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_WHITE = 0xFFFFFF

-- 功能列表（每个卡片2列，参考 home_win 风格）
-- 注: 以太网状态已包含在网络状态页中(以太网1/以太网2), 不再单独提供入口
local demos = {
    { name = "网络状态", color = 0x4CAF50 },
    { name = "WiFi",     color = 0x2196F3 },
    { name = "RS485",    color = 0xFF9800 },
    { name = "RS232",    color = 0x795548 },
    { name = "DI状态",   color = 0x009688 },
    { name = "RELOAD",   color = 0x666666 },
    { name = "DO控制",   color = 0xF44336 },
    { name = "蜂鸣器",   color = 0x607D8B },
    { name = "状态灯",   color = 0xFFC107 },
    { name = "看门狗",   color = 0xE91E63 },
    { name = "Flash存储", color = 0x8E44AD },
    { name = "系统信息", color = 0x2E4053 },
}

-- 预创建12个命名点击函数（无闭包、无匿名函数）
local function on_network_click()
    sys.publish("OPEN_NETWORK_WIN")
end
local function on_wifi_click()
    sys.publish("OPEN_WIFI_WIN")
end
local function on_rs485_click()
    sys.publish("OPEN_RS485_WIN")
end
local function on_rs232_click()
    sys.publish("OPEN_RS232_WIN")
end
local function on_di_click()
    sys.publish("OPEN_DI_WIN")
end
local function on_reload_click()
    sys.publish("OPEN_RELOAD_WIN")
end
local function on_do_click()
    sys.publish("OPEN_DO_WIN")
end
local function on_buzzer_click()
    sys.publish("OPEN_BUZZER_WIN")
end
local function on_led_click()
    sys.publish("OPEN_LED_WIN")
end
local function on_watchdog_click()
    sys.publish("OPEN_WATCHDOG_WIN")
end
local function on_flash_click()
    sys.publish("OPEN_FLASH_WIN")
end
local function on_sysinfo_click()
    sys.publish("OPEN_SYSINFO_WIN")
end

-- 将点击函数加入表
local click_funcs = {
    on_network_click, on_wifi_click,
    on_rs485_click, on_rs232_click, on_di_click,
    on_reload_click, on_do_click, on_buzzer_click,
    on_led_click, on_watchdog_click, on_flash_click,
    on_sysinfo_click,
}

local function create_ui()
    -- 主容器
    main_container = airui.container({
        x = 0, y = 0, w = 480, h = 272, color = COLOR_BG,
    })

    -- 标题栏（参考 home_win 风格）
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY,
    })
    airui.label({
        parent = title_bar,
        text = "Air8301 硬件测试",
        x = 10, y = 12, w = 300, h = 24, font_size = 18,
    })
    -- 时间
    current_time = os.date("%H:%M")
    time_label = airui.label({
        parent = title_bar,
        x = 380, y = 12, w = 90, h = 24,
        text = current_time, font_size = 16, color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 滚动容器（参考 home_win 风格）
    scroll_container = airui.container({
        parent = main_container,
        x = 0, y = 44, w = 480, h = 228, color = COLOR_BG,
    })

    -- 2列网格布局（参考 home_win：button_width=225, button_height=60, padding=10）
    local button_width = 225
    local button_height = 65
    local columns = 2
    local padding = 10
    local y_offset = 0

    for i, demo in ipairs(demos) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local x = padding + col * (button_width + padding)
        local y = y_offset + row * (button_height + padding)

        -- 卡片
        local card = airui.container({
            parent = scroll_container,
            x = x, y = y,
            w = button_width, h = button_height,
            color = demo.color, radius = 8,
            on_click = click_funcs[i],
        })

        -- 名称标签（居中显示，参考 home_win 风格用 label）
        airui.label({
            parent = card,
            text = demo.name,
            x = 0, y = 12, w = button_width, h = 40,
            font_size = 20, color = COLOR_WHITE,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    scroll_container = nil
    time_label = nil
    win_id = nil
end

local function on_get_focus()
    current_time = os.date("%H:%M")
    if time_label then time_label:set_text(current_time) end
end

local function on_lose_focus() end

local function open_handler()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
    end
end

-- LCD/AirUI 初始化完成 → 开启背光并打开首页
local function on_display_ready()
    sys.publish("BACKLIGHT_ON")
    open_handler()
end

sys.subscribe("DISPLAY_READY", on_display_ready)
