--[[
@module  reload_win
@summary RELOAD按键状态页面，显示按键按下/抬起状态、按住时间和长按5秒恢复出厂进度（8301出厂固件）
@version 1.0
@date    2026.10.09
@author  江访
@version_note v1.1 修复：「按住时间」恒为 0 ms、「恢复出厂进度」进度条不动；
              现在按下期间每 100ms 按真实时长刷新，进度条按 5000ms 目标线性增长

@usage
本页面显示RELOAD（WAKEUP2）按键状态：
1、当前状态（等待中/已按下/已抬起）
2、按住时间（ms，按下期间每 100ms 刷新，抬起后保留最终值）
3、长按5秒恢复出厂进度条（按住期间 0~100% 线性增长，抬起后保留当次结果）
监听 KEY_EVENT 消息（由 reload_app 发布）。

视觉：ui_theme 深色玻璃态（2 条键值行 + 进度面板）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local status_label, held_time_label, progress_bar

-- 布局常量（内容区 464×210：46 + 8 + 46 + 8 + 78 = 186）
local ROW_H      = 46
local ROW_GAP    = 8
local PROGRESS_H = 78
-- 按住时间 / 进度刷新周期（ms）
local TICK_MS = 100
-- 长按恢复出厂目标时长（ms）
-- 须与 reload_app.RESET_HOLD_MS 保持一致：reload_app 在按住 5 秒时发布 FACTORY_RESET_REQUEST
local HOLD_TARGET_MS = 5000

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
刷新「按住时间」与「恢复出厂进度」

elapsed = 当前时刻 - 按下时刻；进度 = elapsed / HOLD_TARGET_MS，夹到 100。

@local
@function update_hold
]]
local function update_hold()
    if not press_start_ms then return end
    local elapsed = mcu.ticks() - press_start_ms
    if elapsed < 0 then elapsed = 0 end

    if held_time_label then
        held_time_label:set_text(elapsed .. " ms")
        held_time_label:set_color(theme.C.t1)
    end

    if progress_bar then
        local pct = math.floor(elapsed * 100 / HOLD_TARGET_MS)
        if pct > 100 then pct = 100 end
        progress_bar:set_value(pct)
    end
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
        -- 开始计时：记录按下时刻并启动周期刷新（进度条由 0 重新增长）
        press_start_ms = mcu.ticks()
        if progress_bar then
            progress_bar:set_value(0)
        end
        update_hold()
        stop_tick()
        tick_timer = sys.timerLoopStart(update_hold, TICK_MS)
    elseif event == "reload_up" then
        if status_label then
            status_label:set_text("已抬起")
            status_label:set_color(theme.SEM.danger)
        end
        -- 收尾：先刷新出最终按住时长与进度，再停止计时并复位
        update_hold()
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

    local y = ctx.y

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
    y = y + ROW_H + ROW_GAP

    -- 进度面板
    local progress_card = theme.card(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = PROGRESS_H,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft,
    })
    theme.label(progress_card, {
        x = 12, y = 10, w = ctx.w - 24, h = 19,
        text = "恢复出厂进度（按住5秒）", px_size = 16, color = theme.C.t3,
    })
    progress_bar = theme.bar(progress_card, {
        x = 12, y = 42, w = ctx.w - 24, h = 18,
        min = 0, max = 100, value = 0,
        color = theme.C.amber,
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
    stop_tick()
    press_start_ms = nil
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

sys.subscribe("OPEN_RELOAD_WIN", open_handler)
