--[[
@module  watchdog_win
@summary 看门狗状态页面，显示启用/禁用状态和喂狗时间
@version 1.0.0
@date    2026.07.30
@author  合宙 Air8301
@usage
本页面显示看门狗状态（启用/禁用）、上次喂狗时间。
提供手动喂狗按钮和启用/禁用功能。
监听 WATCHDOG_STATUS / WATCHDOG_LAST_FEED 消息。
发布 WATCHDOG_FEED_REQUEST / WATCHDOG_ENABLE_REQUEST 消息。
]]

local win_id = nil
local main_container, content
local status_label, last_feed_label, timeout_label

-- 颜色常量
local COLOR_PRIMARY = 0x1A5276
local COLOR_BG = 0xD0D0D0
local COLOR_CARD = 0xFFFFFF
local COLOR_TEXT = 0x000000
local COLOR_SECONDARY = 0x000000
local COLOR_WHITE = 0xFFFFFF
local COLOR_GREEN = 0x4CAF50
local COLOR_RED = 0xF44336

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
手动喂狗按钮点击

@local
@function on_feed_click
]]
local function on_feed_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("WATCHDOG_FEED_REQUEST")
    local now = os.date("%H:%M:%S")
    if last_feed_label then
        last_feed_label:set_text(now)
    end
end

--[[
启用喂狗按钮点击

@local
@function on_enable_click
]]
local function on_enable_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("WATCHDOG_ENABLE_REQUEST", true)
    if status_label then
        status_label:set_text("已启用")
        status_label:set_color(COLOR_GREEN)
    end
end

--[[
禁用喂狗按钮点击

@local
@function on_disable_click
]]
local function on_disable_click()
    if not exwin.is_active(win_id) then return end
    sys.publish("WATCHDOG_ENABLE_REQUEST", false)
    if status_label then
        status_label:set_text("已禁用")
        status_label:set_color(COLOR_RED)
    end
end

--[[
看门狗状态消息回调

@local
@function on_watchdog_status
@param enabled boolean 是否启用
@param timeout_sec number 超时秒数
]]
local function on_watchdog_status(enabled, timeout_sec)
    if not exwin.is_active(win_id) then return end
    if status_label then
        if enabled then
            status_label:set_text("已启用")
            status_label:set_color(COLOR_GREEN)
        else
            status_label:set_text("已禁用")
            status_label:set_color(COLOR_RED)
        end
    end
    if timeout_label then
        timeout_label:set_text(tostring(timeout_sec or 240) .. " 秒")
    end
end

--[[
上次喂狗时间消息回调

@local
@function on_watchdog_last_feed
@param timestamp number mcu.ticks()时间戳
]]
local function on_watchdog_last_feed(timestamp)
    if not exwin.is_active(win_id) then return end
    if last_feed_label then
        local time_str = os.date("%H:%M:%S")
        last_feed_label:set_text(time_str)
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
        text = "看门狗",
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
        text = "看门狗状态",
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
        text = "获取中...",
        font_size = 18,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 上次喂狗时间卡片
    local feed_card = airui.container({
        parent = content,
        x = 10,
        y = 80,
        w = 460,
        h = 60,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = feed_card,
        x = 10,
        y = 4,
        w = 100,
        h = 20,
        text = "上次喂狗时间",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    last_feed_label = airui.label({
        parent = feed_card,
        x = 10,
        y = 28,
        w = 200,
        h = 24,
        text = "--:--:--",
        font_size = 18,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 超时时间卡片
    local timeout_card = airui.container({
        parent = content,
        x = 10,
        y = 150,
        w = 460,
        h = 50,
        color = COLOR_CARD,
        radius = 6
    })
    airui.label({
        parent = timeout_card,
        x = 10,
        y = 4,
        w = 100,
        h = 20,
        text = "超时时间",
        font_size = 14,
        color = COLOR_SECONDARY,
        align = airui.TEXT_ALIGN_LEFT
    })
    timeout_label = airui.label({
        parent = timeout_card,
        x = 10,
        y = 26,
        w = 200,
        h = 20,
        text = "240 秒",
        font_size = 16,
        color = COLOR_TEXT,
        align = airui.TEXT_ALIGN_LEFT
    })

    -- 操作按钮区域
    -- 手动喂狗
    local feed_btn = airui.container({
        parent = content,
        x = 10,
        y = 210,
        w = 140,
        h = 40,
        color = COLOR_PRIMARY,
        radius = 6,
        on_click = on_feed_click
    })
    airui.label({
        parent = feed_btn,
        x = 0,
        y = 8,
        w = 140,
        h = 24,
        text = "手动喂狗",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 启用
    local enable_btn = airui.container({
        parent = content,
        x = 170,
        y = 210,
        w = 140,
        h = 40,
        color = COLOR_GREEN,
        radius = 6,
        on_click = on_enable_click
    })
    airui.label({
        parent = enable_btn,
        x = 0,
        y = 8,
        w = 140,
        h = 24,
        text = "启用",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 禁用
    local disable_btn = airui.container({
        parent = content,
        x = 330,
        y = 210,
        w = 140,
        h = 40,
        color = COLOR_RED,
        radius = 6,
        on_click = on_disable_click
    })
    airui.label({
        parent = disable_btn,
        x = 0,
        y = 8,
        w = 140,
        h = 24,
        text = "禁用",
        font_size = 16,
        color = COLOR_WHITE,
        align = airui.TEXT_ALIGN_CENTER
    })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("WATCHDOG_STATUS", on_watchdog_status)
    sys.subscribe("WATCHDOG_LAST_FEED", on_watchdog_last_feed)
    -- 请求当前状态
    sys.publish("WATCHDOG_GET_STATUS_REQUEST")
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
    last_feed_label = nil
    timeout_label = nil
    sys.unsubscribe("WATCHDOG_STATUS", on_watchdog_status)
    sys.unsubscribe("WATCHDOG_LAST_FEED", on_watchdog_last_feed)
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
OPEN_WATCHDOG_WIN 消息处理器

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

sys.subscribe("OPEN_WATCHDOG_WIN", open_handler)
