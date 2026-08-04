--[[
@module  buzzer_win
@summary 蜂鸣器测试页，点击就响0.5秒
@version 1.0.0
@date    2026.07.30
@author  江访
@usage
点击测试按钮蜂鸣器响0.5秒，固定2700Hz。
]]

local win_id = nil
local main_container, content

local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_TEST_BTN = 0xDD4444

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function on_test_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("BUZZER_BEEP_REQUEST")
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 272, color = COLOR_BG, parent = airui.screen })

    -- 顶部导航栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY })
    local back_btn = airui.container({ parent = header, x = 0, y = 0, w = 60, h = 44, on_click = on_back_click })
    airui.label({ parent = back_btn, x = 5, y = 10, w = 50, h = 24, text = "< 返回", font_size = 16, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })
    airui.label({ parent = header, x = 60, y = 8, w = 360, h = 28, text = "蜂鸣器", font_size = 20, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })

    content = airui.container({ parent = main_container, x = 0, y = 44, w = 480, h = 228, color = COLOR_BG })

    -- 说明卡片
    local card = airui.container({ parent = content, x = 10, y = 20, w = 460, h = 80, color = COLOR_CARD, radius = 6 })
    airui.label({ parent = card, x = 15, y = 10, w = 430, h = 24, text = "蜂鸣器测试", font_size = 18, color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })
    airui.label({ parent = card, x = 15, y = 42, w = 430, h = 22, text = "2700Hz | 占空比50% | 响0.5秒", font_size = 16, color = COLOR_TEXT, align = airui.TEXT_ALIGN_LEFT })

    -- 测试按钮
    local test_container = airui.container({ parent = content, x = 40, y = 130, w = 400, h = 60, color = COLOR_TEST_BTN, radius = 10, on_click = on_test_click })
    airui.label({ parent = test_container, x = 0, y = 14, w = 400, h = 32, text = "点击测试蜂鸣器", font_size = 24, color = COLOR_WHITE, align = airui.TEXT_ALIGN_CENTER })
end

local function on_create()
    create_ui()
end

local function on_destroy()
    if main_container then main_container:destroy(); main_container = nil end
    content = nil; win_id = nil
end

local function on_get_focus() end
local function on_lose_focus() end

local function open_handler()
    win_id = exwin.open({ on_create = on_create, on_destroy = on_destroy, on_lose_focus = on_lose_focus, on_get_focus = on_get_focus })
end

sys.subscribe("OPEN_BUZZER_WIN", open_handler)
