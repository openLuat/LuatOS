--[[
@module  reload_win
@summary RELOAD按键状态页面，显示按键按下/抬起状态和按住时间
@version 1.0.0
@date    2026.07.30
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

-- 颜色常量
local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_GREEN = 0x4CAF50
local COLOR_RED = 0xF44336
local COLOR_ORANGE = 0xFF9800

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
            status_label:set_color(COLOR_GREEN)
        end
        if progress_bar then
            progress_bar:set_value(0)
        end
    elseif event == "reload_up" then
        if status_label then
            status_label:set_text("已抬起")
            status_label:set_color(COLOR_RED)
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
    main_container = airui.container({ x = 0, y = 0, w = 480, h = 272, color = COLOR_BG, parent = airui.screen })

    -- 顶部导航栏
    local header = airui.container({ parent = main_container, x = 0, y = 0, w = 480, h = 44, color = COLOR_PRIMARY })

    -- 返回按钮
    local back_btn = airui.container({
        parent = header,
        x = 0,
        y = 0,
        w = 60,
        h = 44,
        on_click = on_back_click
    })
    airui.label({
        parent = back_btn,
        x = 5,
        y = 10,
        w = 50,
        h = 24,
        text = "< 返回",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 标题
    airui.label({
        parent = header,
        x = 60,
        y = 8,
        w = 360,
        h = 28,
        text = "RELOAD按键",
        font_size = 20,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域
    content = airui.container({
        parent = main_container,
        x = 0,
        y = 44,
        w = 480,
        h = 228,
        color = COLOR_BG
    })

    -- 状态卡片
    local status_card = airui.container({
        parent = content,
        x = 10,
        y = 10,
        w = 460,
        h = 60,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = status_card,
        x = 10,
        y = 4,
        w = 80,
        h = 20,
        text = "按键状态",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    status_label = airui.label({
        parent = status_card,
        x = 10,
        y = 28,
        w = 200,
        h = 24,
        text = "等待中...",
        font_size = 18,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 按住时间卡片
    local time_card = airui.container({
        parent = content,
        x = 10,
        y = 80,
        w = 460,
        h = 60,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = time_card,
        x = 10,
        y = 4,
        w = 100,
        h = 20,
        text = "按住时间",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    held_time_label = airui.label({
        parent = time_card,
        x = 10,
        y = 28,
        w = 200,
        h = 24,
        text = "0 ms",
        font_size = 18,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 进度条卡片
    local progress_card = airui.container({
        parent = content,
        x = 10,
        y = 150,
        w = 460,
        h = 60,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = progress_card,
        x = 10,
        y = 4,
        w = 200,
        h = 20,
        text = "恢复出厂进度（按住5秒）",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    progress_bar = airui.bar({
        parent = progress_card,
        x = 10,
        y = 28,
        w = 440,
        h = 20,
        min = 0,
        max = 100,
        value = 0,
        indicator_color = COLOR_ORANGE,
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
