--[[
@module  prod_watchdog_win
@summary 看门狗状态页面（产测模式），显示启用/禁用状态和喂狗时间
@version 1.0
@date    2026.10.08
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_WATCHDOG_WIN，避免与业务页面冲突

@usage
本页面显示看门狗状态（启用/禁用）、上次喂狗时间、超时时间。
提供手动喂狗按钮和启用/禁用功能。
监听 WATCHDOG_STATUS / WATCHDOG_LAST_FEED 消息。
发布 WATCHDOG_FEED_REQUEST / WATCHDOG_ENABLE_REQUEST 消息（由共享的 watchdog_app 处理）。

视觉：ui_theme 深色玻璃态（3 条键值行 + 一排语义色按钮）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local status_label, last_feed_label, timeout_label

-- 布局常量（内容区 464×210）
local ROW_H   = 42
local ROW_GAP = 6
local BTN_H   = 34
local BTN_GAP = 8

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
        status_label:set_color(theme.SEM.success)
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
        status_label:set_color(theme.SEM.danger)
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
            status_label:set_color(theme.SEM.success)
        else
            status_label:set_text("已禁用")
            status_label:set_color(theme.SEM.danger)
        end
    end
    if timeout_label then
        timeout_label:set_text(tostring(timeout_sec or 240) .. " 秒")
        timeout_label:set_color(theme.C.t1)
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
        last_feed_label:set_color(theme.C.t1)
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "看门狗", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    local y = ctx.y

    -- 看门狗状态
    local _, l_status = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H,
        label = "看门狗状态", value = "获取中...", value_color = theme.C.t2 })
    status_label = l_status
    y = y + ROW_H + ROW_GAP

    -- 上次喂狗时间
    local _, l_feed = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H,
        label = "上次喂狗时间", value = "--:--:--", value_color = theme.C.t2 })
    last_feed_label = l_feed
    y = y + ROW_H + ROW_GAP

    -- 超时时间
    local _, l_timeout = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H,
        label = "超时时间", value = "240 秒", value_color = theme.C.t1 })
    timeout_label = l_timeout
    y = y + ROW_H + 8

    -- 操作按钮（三枚等宽）
    local btn_w = math.floor((ctx.w - BTN_GAP * 2) / 3)
    theme.btn(ctx.base, {
        x = ctx.x, y = y, w = btn_w, h = BTN_H,
        text = "手动喂狗", bg = theme.C.amber, fg = theme.C.on_amber,
        on_click = on_feed_click })
    theme.btn(ctx.base, {
        x = ctx.x + btn_w + BTN_GAP, y = y, w = btn_w, h = BTN_H,
        text = "启用", bg = theme.C.green, fg = theme.C.on_amber,
        on_click = on_enable_click })
    theme.btn(ctx.base, {
        x = ctx.x + 2 * (btn_w + BTN_GAP), y = y, w = btn_w, h = BTN_H,
        text = "禁用", bg = theme.SEM.danger, fg = theme.C.on_amber,
        on_click = on_disable_click })
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
OPEN_PROD_WATCHDOG_WIN 消息处理器

@local
@function open_handler
]]
local function open_handler()
    -- 单实例保护：避免同页多实例并存时互相覆盖 win_id（会使点击准入判定失效）
    if win_id and exwin.is_active(win_id) then return end
    if win_id then
        exwin.close(win_id)
        win_id = nil
    end
    win_id = exwin.open({
        on_create = on_create,
        on_destroy = on_destroy,
        on_lose_focus = on_lose_focus,
        on_get_focus = on_get_focus,
    })
end

sys.subscribe("OPEN_PROD_WATCHDOG_WIN", open_handler)
