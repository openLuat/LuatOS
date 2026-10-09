--[[
@module  fota_win
@summary FOTA 远程升级页面（8301出厂固件）
@version 2.0
@date    2026.10.08
@author  江访

@usage
显示脚本版本、升级状态与进度，提供"检测更新"按钮与升级历史。
- 每 2 秒轮询 fota_app.get_status() 刷新显示

视觉：ui_theme 深色玻璃态（2 条键值行 + 进度条 + 主色按钮 + 历史面板）。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local ver_label, status_label, progress_bar, history_label

local fota_app = require "fota_app"

-- 刷新定时器
local refresh_timer = nil

-- 布局常量（内容区 464×210）
local ROW_H   = 36
local ROW_GAP = 5
local BTN_H   = 30

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
检测更新按钮点击

@local
@function on_check_click
]]
local function on_check_click()
    if not exwin.is_active(win_id) then return end
    if status_label then
        status_label:set_text("正在检测...")
        status_label:set_color(theme.SEM.warning)
    end
    fota_app.check()
end

--[[
刷新 FOTA 状态显示

@local
@function refresh_status
]]
local function refresh_status()
    if not exwin.is_active(win_id) then return end
    local st = fota_app.get_status() or {}

    if ver_label then
        ver_label:set_text(tostring(VERSION or "--"))
        ver_label:set_color(theme.C.t1)
    end

    if status_label then
        local msg = st.msg or st.stage or "--"
        status_label:set_text(msg)
        if st.stage == "error" then
            status_label:set_color(theme.SEM.danger)
        elseif st.stage == "download_done" then
            status_label:set_color(theme.SEM.success)
        else
            status_label:set_color(theme.C.t1)
        end
    end

    if progress_bar then
        progress_bar:set_value(st.progress or 0)
    end

    if history_label and st.history and #st.history > 0 then
        local lines = {}
        for i, item in ipairs(st.history) do
            if i > 2 then break end
            lines[#lines + 1] = tostring(item.time or "--") .. "  "
                .. tostring(item.ver or "--") .. "  " .. tostring(item.status or "")
        end
        history_label:set_text(table.concat(lines, "\n"))
    end
end

--[[
定时刷新回调

@local
@function refresh_timer_cb
]]
local function refresh_timer_cb()
    refresh_status()
end

--[[
创建 FOTA 页面 UI

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "远程升级", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    local y = ctx.y

    local _, l_ver = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 130,
        label = "当前脚本版本", value = "--" })
    ver_label = l_ver
    y = y + ROW_H + ROW_GAP

    local _, l_status = theme.kv_row(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = ROW_H, label_w = 130,
        label = "升级状态", value = "就绪" })
    status_label = l_status
    y = y + ROW_H + ROW_GAP + 6

    -- 进度条
    progress_bar = theme.bar(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = 14,
        min = 0, max = 100, value = 0, color = theme.C.amber })
    y = y + 14 + 6

    -- 检测更新按钮
    theme.btn(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = BTN_H,
        text = "立即检测更新", on_click = on_check_click })
    y = y + BTN_H + 6

    -- 升级历史面板
    local hh = ctx.h - (y - ctx.y)
    if hh < 40 then hh = 40 end
    local history_card = theme.card(ctx.base, {
        x = ctx.x, y = y, w = ctx.w, h = hh,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft })
    theme.label(history_card, {
        x = 12, y = 6, w = ctx.w - 24, h = 19,
        text = "升级历史", px_size = 16, color = theme.C.t3 })
    history_label = theme.label(history_card, {
        x = 12, y = 28, w = ctx.w - 24, h = hh - 34,
        text = "暂无记录", px_size = 16, color = theme.C.t1 })

    refresh_status()
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    if not refresh_timer then
        refresh_timer = sys.timerLoopStart(refresh_timer_cb, 2000)
    end
end

--[[
窗口销毁回调

@local
@function on_destroy
]]
local function on_destroy()
    if refresh_timer then
        sys.timerStop(refresh_timer)
        refresh_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    content = nil
    ver_label = nil
    status_label = nil
    progress_bar = nil
    history_label = nil
    win_id = nil
end

--[[
窗口获得焦点回调

@local
@function on_get_focus
]]
local function on_get_focus()
    refresh_status()
end

--[[
窗口失去焦点回调

@local
@function on_lose_focus
]]
local function on_lose_focus() end

--[[
OPEN_FOTA_WIN 消息处理器

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

sys.subscribe("OPEN_FOTA_WIN", open_handler)
