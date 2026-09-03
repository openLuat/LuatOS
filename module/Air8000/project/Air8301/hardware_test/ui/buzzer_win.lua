--[[
@module  buzzer_win
@summary 蜂鸣器测试页，点击就响0.5秒
@version 2.0.0
@date    2026.08.14
@author  江访
@usage
点击测试按钮蜂鸣器响0.5秒，固定2700Hz。
]]

local win_id = nil
local main_container, content

local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

local function on_test_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("BUZZER_BEEP_REQUEST")
end

local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    -- 顶部标题栏
    T.titlebar(main_container, "蜂鸣器", on_back_click)

    content = airui.container({ parent = main_container, x = 0, y = T.CONTENT_Y, w = T.SCREEN_W, h = T.CONTENT_H, color = T.COLOR_BG })

    -- 说明卡片
    T.info_card(content, 20, 80, "蜂鸣器测试", "2700Hz | 占空比50% | 响0.5秒")

    -- 测试按钮（红色危险按钮）
    T.btn_danger(content, 40, 130, 400, 30, "点击测试蜂鸣器", on_test_click)
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
