--[[
@module  led_win
@summary 状态灯控制页面，仅手动开关
@version 2.0.0
@date    2026.08.14
@author  江访
@usage
4G灯(GPIO21)和WiFi灯(GPIO141)的ON/OFF开关控制。
]]

local win_id = nil
local main_container, content
local led4g_status_label, ledwifi_status_label
local led4g_state = 0
local ledwifi_state = 0

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
        led4g_status_label:set_color(led4g_state == 1 and T.COLOR_GREEN or T.COLOR_TEXT_SECONDARY)
    end
    sys.publish("LED_SET_REQUEST", 1, led4g_state)
end

-- WiFi灯开关点击
local function on_ledwifi_click()
    if not exwin.is_active(win_id) then return end
    ledwifi_state = ledwifi_state == 0 and 1 or 0
    if ledwifi_status_label then
        ledwifi_status_label:set_text(ledwifi_state == 1 and "已开启" or "已关闭")
        ledwifi_status_label:set_color(ledwifi_state == 1 and T.COLOR_GREEN or T.COLOR_TEXT_SECONDARY)
    end
    sys.publish("LED_SET_REQUEST", 2, ledwifi_state)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    -- 顶部标题栏
    T.titlebar(main_container, "状态灯", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 4G灯控制卡片
    local card1 = airui.container({ parent = content, x = T.MARGIN, y = T.MARGIN, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = card1, x = 10, y = 6, w = 200, h = 24, text = "4G状态灯 (GPIO21)", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 开关按钮（蓝色主按钮）
    T.btn_primary(card1, 10, 34, 140, 30, "开关切换", on_led4g_click)

    led4g_status_label = airui.label({ parent = card1, x = 150, y = 38, w = 200, h = 24, text = "已关闭", font_size = T.FONT_BODY, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })

    -- WiFi灯控制卡片
    local card2 = airui.container({ parent = content, x = T.MARGIN, y = 95, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS })
    airui.label({ parent = card2, x = 10, y = 6, w = 200, h = 24, text = "WiFi状态灯 (GPIO141)", font_size = T.FONT_BODY, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    T.btn_primary(card2, 10, 34, 140, 30, "开关切换", on_ledwifi_click)

    ledwifi_status_label = airui.label({ parent = card2, x = 150, y = 38, w = 200, h = 24, text = "已关闭", font_size = T.FONT_BODY, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
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
