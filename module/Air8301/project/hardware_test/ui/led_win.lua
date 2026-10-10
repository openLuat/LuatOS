--[[
@module  led_win
@summary 状态灯控制页面，切换开关控制
@version 4.0.0
@date    2026.09.03
@author  江访
@usage
4G灯(GPIO21)和WiFi灯(GPIO141)的ON/OFF控制。
整卡可点击，右侧 iOS 风格切换开关。与 do_win 统一风格。
]]

local win_id = nil
local main_container, content
local led4g_track, led4g_knob, ledwifi_track, ledwifi_knob
local led4g_state = 0
local ledwifi_state = 0

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

-- 4G灯切换
local function on_led4g_click()
    if not exwin.is_active(win_id) then return end
    led4g_state = led4g_state == 0 and 1 or 0
    T.toggle_switch_update(led4g_track, led4g_knob, led4g_state == 1)
    sys.publish("LED_SET_REQUEST", 1, led4g_state)
end

-- WiFi灯切换
local function on_ledwifi_click()
    if not exwin.is_active(win_id) then return end
    ledwifi_state = ledwifi_state == 0 and 1 or 0
    T.toggle_switch_update(ledwifi_track, ledwifi_knob, ledwifi_state == 1)
    sys.publish("LED_SET_REQUEST", 2, ledwifi_state)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "状态灯", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 4G灯控制卡片（整卡可点击）
    local card1 = airui.container({ parent = content, x = T.MARGIN, y = T.MARGIN, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS, on_click = on_led4g_click })
    airui.label({ parent = card1, x = 15, y = 10, w = 300, h = 26, text = "4G状态灯", font_size = T.FONT_TITLE, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = card1, x = 15, y = 38, w = 300, h = 22, text = "GPIO21", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    -- 右侧切换开关（OFF）
    led4g_track, led4g_knob = T.toggle_switch(card1, T.CARD_W - 65, 21, false, on_led4g_click)

    -- WiFi灯控制卡片（整卡可点击）
    local card2 = airui.container({ parent = content, x = T.MARGIN, y = 95, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS, on_click = on_ledwifi_click })
    airui.label({ parent = card2, x = 15, y = 10, w = 300, h = 26, text = "WiFi状态灯", font_size = T.FONT_TITLE, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = card2, x = 15, y = 38, w = 300, h = 22, text = "GPIO141", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    ledwifi_track, ledwifi_knob = T.toggle_switch(card2, T.CARD_W - 65, 21, false, on_ledwifi_click)
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    content = nil; led4g_track = nil; led4g_knob = nil; ledwifi_track = nil; ledwifi_knob = nil; win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_LED_WIN", open_handler)
