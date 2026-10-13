--[[
@module  reload_win
@summary RELOAD按键状态页面，显示按键按下/抬起状态和按住时间
@version 2.0.0
@date    2026.08.14
@author  合宙 Air8301
@usage
本页面显示RELOAD（WAKEUP2）按键状态：
1、当前状态（已按下/已抬起）
2、按住时间（ms）
3、按住5秒进度条
4、抬起时显示总按住时间
监听 RELOAD_PRESSED / RELOAD_HELD / RELOAD_RELEASED / RELOAD_FACTORY_RESET 消息。
]]

local win_id = nil
local main_container, content
local status_label, held_time_label, progress_bar

--[[
导航栏返回按钮点击

@local
@function on_back_click
]]
local function on_back_click()
    if not exwin.is_active(win_id) then return end
    exwin.close(win_id)
end

--[[
RELOAD按下消息回调

@local
@function on_key_event
@param event string 按键事件 "reload_down" 或 "reload_up"
]]
local function on_key_event(event)
    if not exwin.is_active(win_id) then return end
    if event == "reload_down" then
        if status_label then
            status_label:set_text("已按下")
            status_label:set_color(T.COLOR_GREEN)
        end
        if progress_bar then
            progress_bar:set_value(0)
        end
    elseif event == "reload_up" then
        if status_label then
            status_label:set_text("已抬起")
            status_label:set_color(T.COLOR_DANGER)
        end
        if progress_bar then
            progress_bar:set_value(0)
        end
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    -- 顶部标题栏
    T.titlebar(main_container, "RELOAD按键", on_back_click)

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = T.CONTENT_Y,
        w = T.SCREEN_W,
        h = T.CONTENT_H,
        color = T.COLOR_BG
    })

    -- 状态卡片
    local _, _, status_content = T.info_card(content, 10, 60, "按键状态", "等待中...")
    status_label = status_content

    -- 按住时间卡片
    local _, _, time_content = T.info_card(content, 80, 60, "按住时间", "0 ms")
    held_time_label = time_content

    -- 进度条卡片
    local progress_card = airui.container({
        parent = content,
        x = T.MARGIN,
        y = 150,
        w = T.CARD_W,
        h = 60,
        color = T.COLOR_CARD,
        radius = T.CARD_RADIUS
    })
    airui.label({
        parent = progress_card,
        x = 10,
        y = 4,
        w = T.CARD_W - 20,
        h = 20,
        text = "恢复出厂进度（按住5秒）",
        font_size = T.FONT_CARD_TITLE,
        color = T.COLOR_TEXT_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    progress_bar = airui.bar({
        parent = progress_card,
        x = 10,
        y = 28,
        w = T.CARD_W - 20,
        h = 20,
        min = 0,
        max = 100,
        value = 0,
        indicator_color = T.COLOR_ORANGE,
    })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("KEY_EVENT", on_key_event)
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    status_label = nil
    held_time_label = nil
    progress_bar = nil
    sys.unsubscribe("KEY_EVENT", on_key_event)
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    -- 不需要特殊处理
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus()
    -- 不需要特殊处理
end

--[[
OPEN_RELOAD_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_RELOAD_WIN", open_handler)
