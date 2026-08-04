--[[
@module  led_win
@summary 状态灯控制页面，仅手动开关
@version 1.0.0
@date    2026.07.30
@author  江访
@usage
4G灯(GPIO21)和WiFi灯(GPIO141)的ON/OFF开关控制。
]]

local win_id = nil
local main_container, content
local led4g_status_label, ledwifi_status_label
local led4g_state = 0
local ledwifi_state = 0

local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_RED = 0xF44336

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

-- 4G灯开关点击
local function on_led4g_click()
    if not exwin.is_active(win_id) then return end
    led4g_state = led4g_state == 0 and 1 or 0
    if led4g_status_label then
        led4g_status_label:set_text(led4g_state == 1 and "已开启" or "已关闭")
    end
    sys.publish("LED_SET_REQUEST", 1, led4g_state)
end

-- WiFi灯开关点击
local function on_ledwifi_click()
    if not exwin.is_active(win_id) then return end
    ledwifi_state = ledwifi_state == 0 and 1 or 0
    if ledwifi_status_label then
        ledwifi_status_label:set_text(ledwifi_state == 1 and "已开启" or "已关闭")
    end
    sys.publish("LED_SET_REQUEST", 2, ledwifi_state)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 272, color = COLOR_BG, parent = airui.screen })

    -- 顶部导航栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY })
    local back_btn = airui.container({ parent = header, x = 0, y = 0, w = 60, h = 44, on_click = on_back_click })
    airui.label({ parent = back_btn, x = 5, y = 10, w = 50, h = 24, text = "< 返回", font_size = 16, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 60, y = 8, w = 360, h = 28, text = "状态灯", font_size = 20, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 44, w = 480, h = 228, color = COLOR_BG })

    -- 4G灯控制卡片
    local card1 = airui.container({ parent = content, x = 10, y = 10, w = 460, h = 70, color = COLOR_CARD, radius = 6 })
    airui.label({ parent = card1, x = 10, y = 6, w = 200, h = 22, text = "4G状态灯 (GPIO21)", font_size = 16, color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 开关按钮（整个按钮带 on_click）
    local btn1 = airui.container({ parent = card1, x = 10, y = 36, w = 120, h = 28, color = COLOR_PRIMARY, radius = 4, on_click = on_led4g_click })
    airui.label({ parent = btn1, x = 0, y = 2, w = 120, h = 24, text = "开关切换", font_size = 14, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })

    led4g_status_label = airui.label({ parent = card1, x = 150, y = 38, w = 200, h = 24, text = "已关闭", font_size = 16, color = COLOR_RED, align = airui.TEXT_ALIGN_LEFT })

    -- WiFi灯控制卡片
    local card2 = airui.container({ parent = content, x = 10, y = 95, w = 460, h = 70, color = COLOR_CARD, radius = 6 })
    airui.label({ parent = card2, x = 10, y = 6, w = 200, h = 22, text = "WiFi状态灯 (GPIO141)", font_size = 16, color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    local btn2 = airui.container({ parent = card2, x = 10, y = 36, w = 120, h = 28, color = COLOR_PRIMARY, radius = 4, on_click = on_ledwifi_click })
    airui.label({ parent = btn2, x = 0, y = 2, w = 120, h = 24, text = "开关切换", font_size = 14, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })

    ledwifi_status_label = airui.label({ parent = card2, x = 150, y = 38, w = 200, h = 24, text = "已关闭", font_size = 16, color = COLOR_RED, align = airui.TEXT_ALIGN_LEFT })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    content = nil
    led4g_status_label = nil
    ledwifi_status_label = nil
    win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_LED_WIN", open_handler)
