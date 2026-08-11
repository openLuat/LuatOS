--[[
@module  do_win
@summary DO控制页面，按钮控制DO1/DO2
@version 1.0.0
@date    2026.07.30
@author  江访
@usage
使用按钮显示继电器状态，点击切换 ON/OFF。
发布 DO_SET_REQUEST(ch, state) 到 do_app。
]]

local win_id = nil
local main_container, content
local do1_btn, do2_btn
local do1_state = 0
local do2_state = 0

local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

-- DO1按钮点击
local function on_do1_click()
    log.info("do_win", "DO1 clicked")
    do1_state = do1_state == 0 and 1 or 0
    if do1_btn then do1_btn:set_text(do1_state == 1 and "ON" or "OFF") end
    sys.publish("DO_SET_REQUEST", 1, do1_state)
end

-- DO2按钮点击
local function on_do2_click()
    log.info("do_win", "DO2 clicked")
    do2_state = do2_state == 0 and 1 or 0
    if do2_btn then do2_btn:set_text(do2_state == 1 and "ON" or "OFF") end
    sys.publish("DO_SET_REQUEST", 2, do2_state)
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 272, color = COLOR_BG, parent = airui.screen })

    -- 顶部导航栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY })
    local back_btn = airui.container({ parent = header, x = 0, y = 0, w = 60, h = 44, on_click = on_back_click })
    airui.label({ parent = back_btn, x = 5, y = 10, w = 50, h = 24, text = "< 返回", font_size = 16, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 60, y = 8, w = 360, h = 28, text = "DO输出", font_size = 20, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 44, w = 480, h = 228, color = COLOR_BG })

    -- DO1 卡片（整个卡片可点击，和状态灯按钮一样）
    local c1 = airui.container({ parent = content, x = 10, y = 20, w = 460, h = 70, color = COLOR_CARD, radius = 6, on_click = on_do1_click })
    airui.label({ parent = c1, x = 15, y = 10, w = 200, h = 24, text = "DO1 继电器", font_size = 18, color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c1, x = 15, y = 38, w = 200, h = 22, text = "GPIO24", font_size = 14, color = COLOR_SECONDARY, align = airui.TEXT_ALIGN_LEFT })

    -- 状态指示（右侧显示 ON/OFF）
    do1_btn = airui.label({ parent = c1, x = 380, y = 15, w = 60, h = 40, text = "OFF",
        font_size = 22, color = COLOR_SECONDARY, align = airui.TEXT_ALIGN_CENTER })

    -- DO2 卡片（整个卡片可点击）
    local c2 = airui.container({ parent = content, x = 10, y = 108, w = 460, h = 70, color = COLOR_CARD, radius = 6, on_click = on_do2_click })
    airui.label({ parent = c2, x = 15, y = 10, w = 200, h = 24, text = "DO2 继电器", font_size = 18, color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = c2, x = 15, y = 38, w = 200, h = 22, text = "GPIO25", font_size = 14, color = COLOR_SECONDARY, align = airui.TEXT_ALIGN_LEFT })

    -- 状态指示
    do2_btn = airui.label({ parent = c2, x = 380, y = 15, w = 60, h = 40, text = "OFF",
        font_size = 22, color = COLOR_SECONDARY, align = airui.TEXT_ALIGN_CENTER })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    content = nil; do1_btn = nil; do2_btn = nil; win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_DO_WIN", open_handler)
