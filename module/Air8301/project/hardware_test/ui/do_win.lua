--[[
@module  do_win
@summary DO控制页面，切换开关控制继电器
@version 4.0.0
@date    2026.09.03
@author  江访
@usage
DO1(GPIO24)/DO2(GPIO25) 继电器控制，整卡可点击，右侧 iOS 风格切换开关。
发布 DO_SET_REQUEST(ch, state) 到 do_app。
]]

local win_id = nil
local main_container, content
local do1_track, do1_knob, do2_track, do2_knob
local do1_state = 0
local do2_state = 0

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

-- DO1 切换
local function on_do1_click()
    if not exwin.is_active(win_id) then return end
    do1_state = do1_state == 0 and 1 or 0
    T.toggle_switch_update(do1_track, do1_knob, do1_state == 1)
    sys.publish("DO_SET_REQUEST", 1, do1_state)
end

-- DO2 切换
local function on_do2_click()
    if not exwin.is_active(win_id) then return end
    do2_state = do2_state == 0 and 1 or 0
    T.toggle_switch_update(do2_track, do2_knob, do2_state == 1)
    sys.publish("DO_SET_REQUEST", 2, do2_state)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    T.titlebar(main_container, "DO输出", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- DO1 卡片（整卡可点击）
    local c1 = airui.container({ parent = content, x = T.MARGIN, y = 20, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS, on_click = on_do1_click })
    airui.label({ parent = c1, x = 15, y = 10, w = 300, h = 26, text = "DO1 继电器", font_size = T.FONT_TITLE, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c1, x = 15, y = 38, w = 300, h = 22, text = "GPIO24", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    -- 右侧切换开关（OFF）
    do1_track, do1_knob = T.toggle_switch(c1, T.CARD_W - 65, 21, false, on_do1_click)

    -- DO2 卡片（整卡可点击）
    local c2 = airui.container({ parent = content, x = T.MARGIN, y = 108, w = T.CARD_W, h = 70, color = T.COLOR_CARD, radius = T.CARD_RADIUS, on_click = on_do2_click })
    airui.label({ parent = c2, x = 15, y = 10, w = 300, h = 26, text = "DO2 继电器", font_size = T.FONT_TITLE, color = T.COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c2, x = 15, y = 38, w = 300, h = 22, text = "GPIO25", font_size = T.FONT_SMALL, color = T.COLOR_TEXT_SECONDARY, align = airui.TEXT_ALIGN_LEFT })
    do2_track, do2_knob = T.toggle_switch(c2, T.CARD_W - 65, 21, false, on_do2_click)
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    content = nil; do1_track = nil; do1_knob = nil; do2_track = nil; do2_knob = nil; win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_DO_WIN", open_handler)
