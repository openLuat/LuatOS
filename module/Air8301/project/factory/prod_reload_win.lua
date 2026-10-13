--[[
@module  prod_reload_win
@summary RELOAD按键状态页面（产测模式），显示按键按下/抬起状态与按住时间
@version 1.0
@date    2026.10.09
@author  江访
@version_note 产测专属：消息名前缀 OPEN_PROD_RELOAD_WIN，避免与业务页面冲突；
              v2.1 修复「按住时间」恒为 0 ms（改为按下期间每 100ms 按真实时长刷新），
              并移除「恢复出厂进度」面板（产测模式下 prod_reload_app 无长按 5 秒恢复出厂逻辑，进度条无意义且具有误导性）

@usage
本页面显示RELOAD（WAKEUP2）按键状态：
1、当前状态（等待中/已按下/已抬起）
2、按住时间（ms，按下期间每 100ms 刷新，抬起后保留最终值）
监听 KEY_EVENT 消息（由 prod_reload_app 发布）。

视觉：ui_theme 深色玻璃态（2 条键值行）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local status_label, held_time_label

-- 布局常量（内容区 464×210：2×46 + 8 = 100，上下居中）
local ROW_H   = 46
local ROW_GAP = 8
-- 按住时间刷新周期（ms）
local TICK_MS = 100

-- 按住计时状态
local press_start_ms = nil
local tick_timer = nil

--[[
停止按住计时定时器（幂等）

@local
@function stop_tick
]]
local function stop_tick()
    if tick_timer then
        sys.timerStop(tick_timer)
        tick_timer = nil
    end
end

--[[
刷新「按住时间」显示：elapsed = 当前时刻 - 按下时刻

@local
@function update_held_time
]]
local function update_held_time()
    if not press_start_ms or not held_time_label then return end
    local elapsed = mcu.ticks() - press_start_ms
    if elapsed < 0 then elapsed = 0 end
    held_time_label:set_text(elapsed .. " ms")
    held_time_label:set_color(theme.C.t1)
end

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
RELOAD按键事件回调

@local
@function on_key_event
@param event string 按键事件 "reload_down" 或 "reload_up"
]]
local function on_key_event(event)
    if not exwin.is_active(win_id) then return end
    if event == "reload_down" then
        if status_label then
            status_label:set_text("已按下")
            status_label:set_color(theme.SEM.success)
        end
        -- 开始计时：记录按下时刻并启动周期刷新
        press_start_ms = mcu.ticks()
        update_held_time()
        stop_tick()
        tick_timer = sys.timerLoopStart(update_held_time, TICK_MS)
    elseif event == "reload_up" then
        if status_label then
            status_label:set_text("已抬起")
            status_label:set_color(theme.SEM.danger)
        end
        -- 收尾：先刷新出最终按住时长，再停止计时并复位
        update_held_time()
        stop_tick()
        press_start_ms = nil
    end
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "RELOAD按键", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- 上下居中：总高 100，内容区 210，顶部留白 55
    local y = ctx.y + math.floor((ctx.h - (ROW_H * 2 + ROW_GAP)) / 2)

    -- 按键状态
    local _, l_status = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 120,
        label = "按键状态", value = "等待中...", value_color = theme.C.t2 })
    status_label = l_status
    y = y + ROW_H + ROW_GAP

    -- 按住时间
    local _, l_held = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 120,
        label = "按住时间", value = "0 ms", value_color = theme.C.t1 })
    held_time_label = l_held
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
    stop_tick()
    press_start_ms = nil
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    status_label = nil
    held_time_label = nil
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
OPEN_PROD_RELOAD_WIN 消息处理器

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

sys.subscribe("OPEN_PROD_RELOAD_WIN", open_handler)
