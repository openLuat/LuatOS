--[[
@module  idle_win
@summary 首页窗口模块，功能菜单网格（图标+文字）
@version 3.0.0
@date    2026.09.03
@author  江访
@usage
首页以4列×3行网格展示12个功能入口，每个入口为32×32图标+文字。
透明容器，图标居中显示在文字上方。对齐 app_engine iOS 风格。
点击后通过发布 OPEN_XXX_WIN 消息跳转。
]]

local win_id = nil
local main_container, time_label

-- 功能列表（图标+文字，透明容器）
-- icon: /luadb/ 下的 PNG 文件名，需提前放入文件系统
local demos = {
    { name = "网络状态",  icon = "/luadb/hw_network.png" },
    { name = "WiFi",      icon = "/luadb/hw_wifi.png" },
    { name = "RS485",     icon = "/luadb/hw_rs485.png" },
    { name = "RS232",     icon = "/luadb/hw_rs232.png" },
    { name = "DI输入",    icon = "/luadb/hw_di.png" },
    { name = "RELOAD",    icon = "/luadb/hw_reload.png" },
    { name = "DO输出",    icon = "/luadb/hw_do.png" },
    { name = "蜂鸣器",    icon = "/luadb/hw_buzzer.png" },
    { name = "状态灯",    icon = "/luadb/hw_led.png" },
    { name = "看门狗",    icon = "/luadb/hw_watchdog.png" },
    { name = "Flash存储", icon = "/luadb/hw_flash.png" },
    { name = "系统信息",  icon = "/luadb/hw_sysinfo.png" },
}

-- 预创建命名点击函数（无闭包）
local function on_network_click()  sys.publish("OPEN_NETWORK_WIN")  end
local function on_wifi_click()     sys.publish("OPEN_WIFI_WIN")     end
local function on_rs485_click()    sys.publish("OPEN_RS485_WIN")    end
local function on_rs232_click()    sys.publish("OPEN_RS232_WIN")    end
local function on_di_click()       sys.publish("OPEN_DI_WIN")       end
local function on_reload_click()   sys.publish("OPEN_RELOAD_WIN")   end
local function on_do_click()       sys.publish("OPEN_DO_WIN")       end
local function on_buzzer_click()   sys.publish("OPEN_BUZZER_WIN")   end
local function on_led_click()      sys.publish("OPEN_LED_WIN")      end
local function on_watchdog_click() sys.publish("OPEN_WATCHDOG_WIN") end
local function on_flash_click()    sys.publish("OPEN_FLASH_WIN")    end
local function on_sysinfo_click()  sys.publish("OPEN_SYSINFO_WIN")  end

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
        x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG,
    })

    -- 标题栏（iOS 蓝色）
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0, w = T.SCREEN_W, h = T.TITLEBAR_H, color = T.COLOR_PRIMARY,
    })
    airui.label({
        parent = title_bar,
        x = 10, y = 15, w = 280, h = T.FONT_TITLE,
        text = "Air8301 硬件测试",
        font_size = T.FONT_TITLE, color = T.COLOR_WHITE,
        align = airui.TEXT_ALIGN_LEFT,
    })
    -- 时间（右对齐）
    local current_time = os.date("%H:%M")
    time_label = airui.label({
        parent = title_bar,
        x = T.SCREEN_W - 100, y = 16, w = 90, h = T.FONT_BODY,
        text = current_time, font_size = T.FONT_BODY, color = T.COLOR_WHITE,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 内容区域
    local content = airui.container({
        parent = main_container,
        x = 0, y = T.TITLEBAR_H, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG,
    })

    -- 4列×3行网格布局（图标+文字，透明容器）
    local icon_size = 32
    local btn_w = 112
    local btn_h = 68
    local columns = 4
    local rows = 3
    local gap_x = 6
    local gap_y = 4
    local total_w = columns * btn_w + (columns - 1) * gap_x  -- 466
    local total_h = rows * btn_h + (rows - 1) * gap_y        -- 212
    local start_x = math.floor((T.SCREEN_W - total_w) / 2)   -- 7
    local start_y = math.floor((T.CONTENT_H - total_h) / 2)  -- 6
    local icon_x = math.floor((btn_w - icon_size) / 2)       -- 40
    local icon_y = 6
    local label_y = icon_y + icon_size + 4                    -- 42

    for i, demo in ipairs(demos) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        local x = start_x + col * (btn_w + gap_x)
        local y = start_y + row * (btn_h + gap_y)

        -- 透明容器（与背景同色，无边框）
        local card = airui.container({
            parent = content,
            x = x, y = y, w = btn_w, h = btn_h,
            color = T.COLOR_BG, border_width = 0, radius = 0,
            on_click = click_funcs[i],
        })

        -- 图标（32×32 PNG，居中显示）
        airui.image({
            parent = card,
            x = icon_x, y = icon_y, w = icon_size, h = icon_size,
            src = demo.icon,
        })

        -- 名称标签（图标下方，水平居中）
        airui.label({
            parent = card,
            x = 0, y = label_y, w = btn_w, h = T.FONT_SMALL,
            text = demo.name,
            font_size = T.FONT_SMALL, color = T.COLOR_TEXT,
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
    time_label = nil
    win_id = nil
end

local function on_get_focus()
    if time_label then
        time_label:set_text(os.date("%H:%M"))
    end
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

sys.subscribe("OPEN_IDLE_WIN", open_handler)
