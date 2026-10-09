--[[
@module  di_win
@summary DI状态页面，显示DI1/DI2输入状态及历史记录（8301出厂固件）
@version 1.0
@date    2026.10.08
@author  江访

@usage
本页面以圆形指示器 + 文字显示DI1和DI2的当前状态（ON/OFF），下方显示状态变更历史记录。
监听 DI_STATUS_CHANGED 消息更新。

视觉：ui_theme 深色玻璃态（状态面板 + 历史面板）。状态圆点由 theme.dot 绘制，
因为内置 hzfont 字库不含实心圆字形。
]]

local theme = require "ui_theme"

local win_id = nil
local main_container, content
local di1_dot, di1_label, di2_dot, di2_label
local history_text_list = {}
local history_label

-- 历史缓存上限（缓存 20 条，受面板高度限制仅显示最新 4 条）
local HISTORY_MAX  = 20
local HISTORY_SHOW = 4

-- 面板几何（内容区 464×210：状态面板 84 + 6 + 历史面板 120 = 210）
local STATE_H   = 84
local STATE_GAP = 6
local DOT_D     = 26

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
刷新单个 DI 通道的指示圆点与文字

@local
@function update_di
@param dot userdata 圆点容器
@param label userdata 状态文字label
@param state boolean 状态（true=ON, false=OFF）
]]
local function update_di(dot, label, state)
    if not dot or not label then return end
    if state then
        dot:set_color(theme.SEM.success, 255)
        label:set_text("ON")
        label:set_color(theme.SEM.success)
    else
        dot:set_color(theme.C.track, 255)
        label:set_text("OFF")
        label:set_color(theme.C.t2)
    end
end

--[[
把历史缓存拼成显示文本（只取最新 HISTORY_SHOW 条）

@local
@function build_history_text
@param list table 历史缓存
@return string 显示文本
]]
local function build_history_text(list)
    local n = #list
    if n == 0 then return "暂无记录" end
    local lines = {}
    local show = n < HISTORY_SHOW and n or HISTORY_SHOW
    for i = 1, show do
        -- 倒序取最新若干条（缓存尾部为最新）
        lines[i] = list[n - i + 1]
    end
    return table.concat(lines, "\n")
end

--[[
DI状态变更消息回调

@local
@function on_di_status_changed
@param di1 boolean DI1状态（true=ON, false=OFF）
@param di2 boolean DI2状态（true=ON, false=OFF）
]]
local function on_di_status_changed(di1, di2)
    if not exwin.is_active(win_id) then return end

    update_di(di1_dot, di1_label, di1)
    update_di(di2_dot, di2_label, di2)

    -- 记录历史
    local time_str = os.date("%H:%M:%S")
    local status_str = "DI1:" .. (di1 and "ON" or "OFF") .. "  DI2:" .. (di2 and "ON" or "OFF")
    table.insert(history_text_list, time_str .. "  " .. status_str)
    if #history_text_list > HISTORY_MAX then
        table.remove(history_text_list, 1)
    end
    if history_label then
        history_label:set_text(build_history_text(history_text_list))
    end
end

--[[
创建单个 DI 通道的显示块（标签 + 圆点 + 状态文字）

@local
@function create_di_block
@param parent userdata 父容器
@param x number 块起始 X 坐标
@param name string 通道名
@return dot userdata 圆点容器
@return label userdata 状态文字label
]]
local function create_di_block(parent, x, name)
    theme.label(parent, {
        x = x + 16, y = 10, w = 100, h = 19,
        text = name, px_size = 16, color = theme.C.t3,
    })
    local dot = theme.dot(parent, {
        x = x + 22, y = 42, d = DOT_D, color = theme.C.track,
    })
    local label = theme.label(parent, {
        x = x + 60, y = 44, w = 120, h = 22,
        text = "OFF", px_size = 18, color = theme.C.t2,
    })
    return dot, label
end

--[[
创建UI界面

@local
@function create_ui
]]
local function create_ui()
    local ctx = theme.page({ title = "DI输入", on_back = on_back_click })
    main_container = ctx.base
    content = ctx.base

    -- 状态面板（左右两个通道）
    local state_card = theme.card(ctx.base, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = STATE_H,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft,
    })
    di1_dot, di1_label = create_di_block(state_card, 0, "DI1")
    di2_dot, di2_label = create_di_block(state_card, 232, "DI2")

    -- 历史面板
    local hy = ctx.y + STATE_H + STATE_GAP
    local hh = ctx.h - STATE_H - STATE_GAP
    if hh < 40 then hh = 40 end
    local history_card = theme.card(ctx.base, {
        x = ctx.x, y = hy, w = ctx.w, h = hh,
        color = theme.C.panel, radius = theme.R.lg, border = theme.C.stroke_soft,
    })
    theme.label(history_card, {
        x = 12, y = 8, w = 200, h = 19,
        text = "状态变更历史", px_size = 16, color = theme.C.t3,
    })
    history_label = theme.label(history_card, {
        x = 12, y = 32, w = ctx.w - 24, h = hh - 40,
        text = "暂无记录", px_size = 16, color = theme.C.t1,
    })
end

--[[
窗口创建回调

@local
@function on_create
]]
local function on_create()
    create_ui()
    sys.subscribe("DI_STATUS_CHANGED", on_di_status_changed)
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
    di1_dot = nil
    di1_label = nil
    di2_dot = nil
    di2_label = nil
    history_label = nil
    history_text_list = {}
    sys.unsubscribe("DI_STATUS_CHANGED", on_di_status_changed)
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
OPEN_DI_WIN 消息处理器

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

sys.subscribe("OPEN_DI_WIN", open_handler)
