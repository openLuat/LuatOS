--[[
@module  watchdog_win
@summary 看门狗状态页面，显示启用/禁用状态和喂狗时间
@version 2.0.0
@date    2026.08.14
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
        status_label:set_color(T.COLOR_GREEN)
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
        status_label:set_color(T.COLOR_DANGER)
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
            status_label:set_color(T.COLOR_GREEN)
        else
            status_label:set_text("已禁用")
            status_label:set_color(T.COLOR_DANGER)
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
    main_container = airui.container({ x = 0, y = 0, w = T.SCREEN_W, h = T.SCREEN_H, color = T.COLOR_BG, parent = airui.screen })

    -- 顶部标题栏
    T.titlebar(main_container, "看门狗", on_back_click)

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
    local _, _, status_content = T.info_card(content, 8, 60, "看门狗状态", "获取中...")
    status_label = status_content

    -- 上次喂狗时间卡片
    local _, _, feed_content = T.info_card(content, 76, 60, "上次喂狗时间", "--:--:--")
    last_feed_label = feed_content

    -- 超时时间卡片
    local _, _, timeout_content = T.info_card(content, 144, 42, "超时时间", "240 秒")
    timeout_label = timeout_content

    -- 操作按钮区域
    local btn_y = 192
    local btn_w = 140
    local btn_h = 30
    local gap = 10
    T.btn_primary(content, T.MARGIN, btn_y, btn_w, btn_h, "手动喂狗", on_feed_click)
    T.btn_success(content, T.MARGIN + btn_w + gap, btn_y, btn_w, btn_h, "启用", on_enable_click)
    T.btn_danger(content, T.MARGIN + 2 * (btn_w + gap), btn_y, btn_w, btn_h, "禁用", on_disable_click)
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
