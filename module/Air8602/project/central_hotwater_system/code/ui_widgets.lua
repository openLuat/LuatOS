--[[
@module  ui_widgets
@summary 通用界面组件库（面板/标题/徽标/进度条/图标/环形/水箱/管道/开关/分段/步进器/卡片）
@version 1.0.0
@date    2026.10.12
@usage
本模块只负责“画控件”，不含任何业务数据；所有颜色来自传入的主题表 T。
各视图模块复用这里的组件，保证风格统一、数据与界面解耦。

滚动条三定律（务必遵守）：
  1) 子控件右/下边界 ≤ 父容器内容区边界 − 2px（边界相等也会被判可滚动）
  2) 文字框高度 ≥ 字号 × 1.5，否则溢出成竖直滚动条
  3) 所有传给 airui 的坐标/尺寸必须是整数（浮点会被 lua_tointeger 判为 0）
]]

local config = require "config"

local W = {}

-- 屏幕密度缩放（设计基准 1024x600）
function W.d(v)
    local s = _G.density_scale or 1
    return math.floor(v * s + 0.5)
end

-- 数值取整
function W.i(v)
    return math.floor((v or 0) + 0.5)
end

-- 全局字号放大系数
W.text_scale = config.text_scale or 1.3

-- 取主题色（语义名 → 颜色）
function W.tone(T, name)
    return (T and T[name]) or 0xFFFFFF
end

-- ============ 基础 ============
function W.label(parent, x, y, w, h, text, size, color, align)
    if text == nil or text == "" then text = " " end
    local fs = math.floor(size * (W.text_scale or 1) + 0.5)
    local lh = math.max(h, math.floor(fs * 1.5 + 0.5))
    local ny = y + math.floor((h - lh) / 2 + 0.5)
    -- 左边界保护：带 1px 边框的容器内容区从 1 开始
    local lx, lw = x, w
    if lx < 1 then
        lw = lw - (1 - lx)
        lx = 1
    end
    return airui.label({
        parent = parent,
        x = W.d(lx), y = W.d(ny), w = W.d(lw), h = W.d(lh),
        text = text,
        font_size = W.d(fs),
        color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

function W.divider(parent, x, y, w, color)
    return airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = 1,
        color = color,
    })
end

function W.panel(parent, x, y, w, h, T, radius, no_corner)
    local c = airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        color = T.panel,
        radius = W.d(radius or 14),
        border_color = T.ring,
        border_width = 1,
    })
    if not no_corner then
        -- 角标内缩 2px，贴边界会触发滚动条
        airui.container({ parent = c, x = W.d(w - 14), y = 2, w = W.d(11), h = 1, color = T.accent_line })
        airui.container({ parent = c, x = W.d(w - 4), y = 2, w = 1, h = W.d(11), color = T.accent_line })
    end
    -- 顶部内高光（模拟设计稿卡片 inset 高光），强化卡片与背景的层次分离；两端避开圆角
    airui.container({ parent = c, x = W.d(14), y = 1, w = W.d(w - 28), h = 1,
        color = 0xFFFFFF, color_opacity = 28 })
    return c
end

function W.panel_title(panel, px, py, w, title, sub, T)
    local cy = py + 3
    airui.container({
        parent = panel, x = W.d(px), y = W.d(cy - 6),
        w = W.d(3), h = W.d(12), color = T.cyan, radius = W.d(2),
    })
    W.label(panel, px + 9, cy - 12, w - 90, 24, title, 13, T.text)
    if sub and sub ~= "" then
        return W.label(panel, px, cy - 9, w - 18, 20, sub, 10, T.text_dim, airui.TEXT_ALIGN_RIGHT)
    end
    return nil
end

function W.chip(parent, x, y, w, text, dot_color, T)
    local c = airui.container({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(26),
        radius = W.d(9), color = T.chip_bg, border_color = T.ring, border_width = 1,
    })
    local tx = 10
    if dot_color then
        airui.container({
            parent = c, x = W.d(10), y = W.d(10),
            w = W.d(6), h = W.d(6), radius = W.d(3), color = dot_color,
        })
        tx = 21
    end
    W.label(c, tx, 3, w - tx - 8, 20, text, 11, T.chip_text, airui.TEXT_ALIGN_LEFT)
    return c
end

-- 徽标（胶囊）：tone ∈ ok/run/warn/off/err
local BADGE_TONE = {
    ok  = { bg = "green", fg = 0x0A2218 },
    run = { bg = "cyan",  fg = 0x04222B },
    warn = { bg = "amber", fg = 0x2A1602 },
    err = { bg = "red",   fg = 0x2A0409 },
    off = { bg = "chip_bg", fg = nil },
}
function W.badge(parent, x, y, w, h, text, tone, T)
    local spec = BADGE_TONE[tone] or BADGE_TONE.off
    local bg = T[spec.bg] or T.chip_bg
    local fg = spec.fg or T.text_soft
    local c = airui.container({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        radius = W.d(math.floor(h / 2)), color = bg,
    })
    W.label(c, 3, 1, w - 6, h - 2, text, math.max(9, h / 2.6), fg, airui.TEXT_ALIGN_CENTER)
    return c
end

-- 水平进度条（pct 0..100）
function W.bar(parent, x, y, w, h, pct, color, bg)
    return airui.bar({
        parent = parent,
        x = W.d(x), y = W.d(y), w = W.d(w), h = math.max(2, W.d(h)),
        min = 0, max = 100, value = math.floor(pct + 0.5),
        radius = W.d(math.floor(h / 2)),
        border_width = 0,
        bg_color = bg,
        indicator_color = color,
    })
end

-- ============ 图标（矢量）============
local ICON_BUILDERS = {}

ICON_BUILDERS.dash = function(c)
    return {
        { type = "line", x1 = 4, y1 = 13, x2 = 20, y2 = 13, color = c, width = 2 },
        { type = "line", x1 = 6, y1 = 17, x2 = 18, y2 = 17, color = c, width = 2 },
        { type = "line", x1 = 13, y1 = 12, x2 = 20, y2 = 5, color = c, width = 2 },
        { type = "circle", cx = 12, cy = 13, r = 2, color = c, width = 2 },
    }
end

ICON_BUILDERS.ctrl = function(c)
    return {
        { type = "line", x1 = 4, y1 = 7, x2 = 20, y2 = 7, color = c, width = 2 },
        { type = "line", x1 = 4, y1 = 17, x2 = 20, y2 = 17, color = c, width = 2 },
        { type = "circle", cx = 15, cy = 7, r = 2, color = c, width = 2 },
        { type = "circle", cx = 9, cy = 17, r = 2, color = c, width = 2 },
    }
end

ICON_BUILDERS.chart = function(c)
    local items = {
        { type = "line", x1 = 4, y1 = 4, x2 = 4, y2 = 19, color = c, width = 2 },
        { type = "line", x1 = 4, y1 = 19, x2 = 20, y2 = 19, color = c, width = 2 },
    }
    local pts = { { 6, 15 }, { 10, 10 }, { 14, 13 }, { 18, 7 } }
    for i = 1, #pts - 1 do
        items[#items + 1] = { type = "line", x1 = pts[i][1], y1 = pts[i][2],
            x2 = pts[i + 1][1], y2 = pts[i + 1][2], color = c, width = 2 }
    end
    return items
end

ICON_BUILDERS.alarm = function(c)
    return {
        { type = "line", x1 = 12, y1 = 3, x2 = 21, y2 = 19, color = c, width = 2 },
        { type = "line", x1 = 12, y1 = 3, x2 = 3, y2 = 19, color = c, width = 2 },
        { type = "line", x1 = 3, y1 = 19, x2 = 21, y2 = 19, color = c, width = 2 },
        { type = "line", x1 = 12, y1 = 9, x2 = 12, y2 = 14, color = c, width = 2 },
    }
end

ICON_BUILDERS.param = function(c)
    return {
        { type = "line", x1 = 4, y1 = 7, x2 = 20, y2 = 7, color = c, width = 2 },
        { type = "line", x1 = 4, y1 = 12, x2 = 20, y2 = 12, color = c, width = 2 },
        { type = "line", x1 = 4, y1 = 17, x2 = 20, y2 = 17, color = c, width = 2 },
        { type = "circle", cx = 9, cy = 7, r = 2, color = c, width = 2 },
        { type = "circle", cx = 15, cy = 12, r = 2, color = c, width = 2 },
        { type = "circle", cx = 8, cy = 17, r = 2, color = c, width = 2 },
    }
end

ICON_BUILDERS.sys = function(c)
    return {
        { type = "rect", x = 6, y = 6, w = 12, h = 12, radius = 2, color = c, width = 2 },
        { type = "rect", x = 10, y = 10, w = 4, h = 4, radius = 1, color = c, width = 2 },
    }
end

-- 泵（圆形 + 口）
ICON_BUILDERS.pump = function(c)
    return {
        { type = "circle", cx = 10, cy = 10, r = 7, color = c, width = 2 },
        { type = "line", x1 = 10, y1 = 3, x2 = 10, y2 = 7, color = c, width = 2 },
        { type = "line", x1 = 14, y1 = 10, x2 = 10, y2 = 10, color = c, width = 2 },
        { type = "line", x1 = 3, y1 = 17, x2 = 6, y2 = 17, color = c, width = 2 },
        { type = "line", x1 = 14, y1 = 17, x2 = 17, y2 = 17, color = c, width = 2 },
    }
end

-- 水滴（阀/上水）
ICON_BUILDERS.drop = function(c)
    return {
        { type = "line", x1 = 10, y1 = 3, x2 = 5, y2 = 10, color = c, width = 2 },
        { type = "line", x1 = 10, y1 = 3, x2 = 15, y2 = 10, color = c, width = 2 },
        { type = "line", x1 = 5, y1 = 10, x2 = 6, y2 = 14, color = c, width = 2 },
        { type = "line", x1 = 15, y1 = 10, x2 = 14, y2 = 14, color = c, width = 2 },
        { type = "line", x1 = 6, y1 = 14, x2 = 10, y2 = 17, color = c, width = 2 },
        { type = "line", x1 = 14, y1 = 14, x2 = 10, y2 = 17, color = c, width = 2 },
    }
end

-- 闪电（电加热）
ICON_BUILDERS.bolt = function(c)
    return {
        { type = "line", x1 = 12, y1 = 3, x2 = 7, y2 = 11, color = c, width = 2 },
        { type = "line", x1 = 7, y1 = 11, x2 = 11, y2 = 11, color = c, width = 2 },
        { type = "line", x1 = 11, y1 = 11, x2 = 8, y2 = 18, color = c, width = 2 },
        { type = "line", x1 = 8, y1 = 18, x2 = 14, y2 = 9, color = c, width = 2 },
        { type = "line", x1 = 14, y1 = 9, x2 = 10, y2 = 9, color = c, width = 2 },
    }
end

-- 循环箭头（温差循环）
ICON_BUILDERS.loop = function(c)
    return {
        { type = "ellipse", cx = 10, cy = 10, rx = 7, ry = 7, color = c, width = 2 },
        { type = "line", x1 = 10, y1 = 3, x2 = 13, y2 = 5, color = c, width = 2 },
        { type = "line", x1 = 10, y1 = 3, x2 = 8, y2 = 6, color = c, width = 2 },
    }
end

-- 回水（箭头回转）
ICON_BUILDERS.back = function(c)
    return {
        { type = "line", x1 = 4, y1 = 7, x2 = 16, y2 = 7, color = c, width = 2 },
        { type = "line", x1 = 16, y1 = 7, x2 = 16, y2 = 14, color = c, width = 2 },
        { type = "line", x1 = 4, y1 = 7, x2 = 4, y2 = 14, color = c, width = 2 },
        { type = "line", x1 = 4, y1 = 7, x2 = 7, y2 = 4, color = c, width = 2 },
        { type = "line", x1 = 4, y1 = 7, x2 = 7, y2 = 10, color = c, width = 2 },
    }
end

-- 加热带/电热
ICON_BUILDERS.coil = function(c)
    local items = {}
    for k = 0, 4 do
        local x = 4 + k * 3
        items[#items + 1] = { type = "line", x1 = x, y1 = 4, x2 = x, y2 = 16, color = c, width = 2 }
    end
    return items
end

-- 温度计
ICON_BUILDERS.thermo = function(c)
    return {
        { type = "line", x1 = 9, y1 = 3, x2 = 9, y2 = 13, color = c, width = 2 },
        { type = "line", x1 = 12, y1 = 3, x2 = 12, y2 = 13, color = c, width = 2 },
        { type = "circle", cx = 10, cy = 15, r = 3, color = c, width = 2, fill = true, fill_color = c },
    }
end

local function icon_items(name, size, color)
    local builder = ICON_BUILDERS[name]
    if not builder then return nil end
    local s = W.d(size) / 20
    local items = builder(color)
    for _, it in ipairs(items) do
        for k, v in pairs(it) do
            if type(v) == "number" and k ~= "color" and k ~= "fill_color" then
                it[k] = W.i(v * s)
            end
        end
        if (it.width or 1) < 1 then it.width = 1 end
    end
    return items
end

function W.icon(parent, name, x, y, size, color)
    local items = icon_items(name, size, color)
    if not items then return nil end
    return airui.shape({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(size), h = W.d(size), items = items,
    })
end

-- 图标原地改色（只重解析 items，不销毁重建）
function W.icon_set_color(shape, name, size, color)
    if not shape then return end
    local items = icon_items(name, size, color)
    if items then shape:set_items(items) end
end

-- ============ 自绘：弧形（多段折线逼近 arc）============
local function arc_items(cx, cy, r, a0, a1, color, width)
    local items = {}
    local step = 8
    local n = math.max(1, math.ceil(math.abs(a1 - a0) / step))
    local px, py
    for i = 0, n do
        local a = math.rad(a0 + (a1 - a0) * i / n)
        local x = W.i(cx + r * math.cos(a))
        local y = W.i(cy + r * math.sin(a))
        if px then
            items[#items + 1] = { type = "line", x1 = px, y1 = py, x2 = x, y2 = y,
                color = color, width = width, round_start = true, round_end = true }
        end
        px, py = x, y
    end
    return items
end

-- 环形仪表：返回 handle:set(pct0..1, color)
-- start_deg/sweep_deg：0°=右，顺时针为正（屏幕坐标 y 向下）
function W.ring(parent, x, y, size, stroke, start_deg, sweep_deg, color_track)
    local cx, cy = math.floor(size / 2), math.floor(size / 2)
    local r = math.floor(size / 2) - math.floor(stroke / 2) - 1
    local track = airui.shape({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(size), h = W.d(size),
        items = arc_items(cx, cy, r, start_deg, start_deg + sweep_deg, color_track, stroke),
    })
    local fill = airui.shape({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(size), h = W.d(size), items = {},
    })
    local h = { track = track, fill = fill, cx = cx, cy = cy, r = r, start = start_deg, sweep = sweep_deg, stroke = stroke }
    function h.set(pct, color)
        pct = math.max(0, math.min(1, pct or 0))
        if pct <= 0.001 then fill:set_items({}); return end
        fill:set_items(arc_items(cx, cy, r, start_deg, start_deg + sweep_deg * pct, color, stroke))
    end
    return h
end

-- spark 折线（温度卡小图）：返回 handle:update(hist, color)
function W.spark(parent, x, y, w, h, color)
    local shape = airui.shape({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h), items = {},
    })
    local hh = { shape = shape }
    function hh.update(hist, col)
        col = col or color
        local n = #hist
        if n < 2 then shape:set_items({}); return end
        local mn, mx = hist[1], hist[1]
        for i = 1, n do
            if hist[i] < mn then mn = hist[i] end
            if hist[i] > mx then mx = hist[i] end
        end
        local span = (mx - mn)
        if span <= 0 then span = 1 end
        local items = {}
        local px, py
        for i = 1, n do
            local xx = W.i((i - 1) / (n - 1) * (w - 2))
            local yy = W.i((h - 3) - (hist[i] - mn) / span * (h - 6))
            if px then
                items[#items + 1] = { type = "line", x1 = px, y1 = py, x2 = xx, y2 = yy,
                    color = col, width = 2, round_start = true, round_end = true }
            end
            px, py = xx, yy
        end
        shape:set_items(items)
    end
    return hh
end

-- 水箱水位：返回 handle:set(pct0..1)
function W.tank(parent, x, y, w, h, T, water_color)
    -- 外框（描边）
    local shape = airui.shape({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        items = {
            { type = "rect", x = 0, y = 0, w = W.i(w - 1), h = W.i(h - 1),
              radius = W.i(12), color = T.ring, width = 2 },
        },
    })
    -- 水体（动态）
    local water = airui.shape({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h), items = {},
    })
    local hd = { shape = water }
    local wx, wh = W.i(w), W.i(h)
    function hd.set(pct, color)
        pct = math.max(0, math.min(1, pct or 0))
        local fill_h = W.i((wh - 4) * pct)
        local items = {}
        if fill_h >= 2 then
            local top = wh - 2 - fill_h
            items[#items + 1] = { type = "rect", x = 3, y = top, w = wx - 6, h = fill_h,
                color = color or water_color, width = 1, fill = true,
                fill_color = color or water_color, fill_opacity = 200 }
            -- 水面线
            items[#items + 1] = { type = "line", x1 = 3, y1 = top, x2 = wx - 3, y2 = top,
                color = color or water_color, width = 2 }
        end
        water:set_items(items)
    end
    return hd
end

-- 管道（虚线流动感：静态虚线）
function W.pipe(parent, x, y, w, color, dim_color)
    return airui.shape({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(20), items = {
            { type = "line", x1 = 2, y1 = 10, x2 = W.i(w - 3), y2 = 10, color = dim_color, width = 6 },
            { type = "line", x1 = 2, y1 = 10, x2 = W.i(w - 3), y2 = 10, color = color, width = 6,
              dash_width = 8, dash_gap = 10 },
        },
    })
end

-- ============ 交互控件 ============
-- 开关（轨道 + 滑块）
function W.toggle(parent, x, y, checked, on_change, T)
    local state = { on = checked and true or false }
    local sw, sh = 42, 22
    local function apply()
        local on = state.on
        state.track:set_color(on and T.accent_soft or T.toggle_off, 255)
        state.track:set_border_color(on and T.cyan or T.ring, 1)
        state.knob:set_color(on and T.cyan or T.toggle_knob, 255)
        state.knob:set_pos(W.d(on and 22 or 2), W.d(2))
    end
    state.track = airui.container({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(sw), h = W.d(sh),
        radius = W.d(math.floor(sh / 2)), color = T.toggle_off,
        border_color = T.ring, border_width = 1,
        on_click = function()
            state.on = not state.on
            apply()
            if on_change then on_change(state.on) end
        end,
    })
    state.knob = airui.container({
        parent = state.track, x = W.d(2), y = W.d(2), w = W.d(sh - 6), h = W.d(sh - 6),
        radius = W.d(math.floor((sh - 6) / 2)), color = T.toggle_knob,
    })
    apply()
    return {
        set = function(v) state.on = v and true or false; apply() end,
        get = function() return state.on end,
    }
end

-- 分段选择
function W.seg(parent, x, y, w, h, options, active, on_change, T)
    local ow = math.floor((w - 4) / #options)
    local holders, labels = {}, {}
    local current = active or 1
    local function apply()
        for i = 1, #options do
            local on = (i == current)
            holders[i]:set_color(on and T.accent_soft or T.panel, 255)
            labels[i]:set_color(on and T.cyan or T.text_dim)
        end
    end
    local outer = airui.container({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        radius = W.d(9), color = T.panel, border_color = T.ring, border_width = 1,
    })
    for i, opt in ipairs(options) do
        local ox = 1 + (i - 1) * ow
        local holder = airui.container({
            parent = outer, x = W.d(ox), y = 2, w = W.d(ow), h = W.d(h - 6),
            color = T.panel,
            on_click = function()
                current = i
                apply()
                if on_change then on_change(i, opt) end
            end,
        })
        labels[i] = W.label(holder, 1, 2, ow - 3, h - 8, opt, 11, T.text_dim, airui.TEXT_ALIGN_CENTER)
        holders[i] = holder
    end
    apply()
    return { set = function(i) if i >= 1 and i <= #options then current = i; apply() end end }
end

-- 步进器（- 值 +）：返回 handle:set(text)
function W.stepper(parent, x, y, w, text, on_step, T)
    local btn_style = {
        bg_color = T.panel, border_color = T.ring, border_width = 1,
        radius = W.d(5), text_color = T.text_soft, pressed_bg_color = T.accent_soft,
    }
    airui.button({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(24), h = W.d(26),
        text = "-", font_size = W.d(17), style = btn_style,
        on_click = function() if on_step then on_step(-1) end end,
    })
    local val = W.label(parent, x + 26, y + 1, w - 52, 24, text, 12, T.text_bright, airui.TEXT_ALIGN_CENTER)
    airui.button({
        parent = parent, x = W.d(x + w - 24), y = W.d(y), w = W.d(24), h = W.d(26),
        text = "+", font_size = W.d(17), style = btn_style,
        on_click = function() if on_step then on_step(1) end end,
    })
    return { set = function(t) val:set_text(t) end }
end

-- 键值行（左键 + 右值）：键、值各占固定区，避免长文本互相重叠
-- val_w：右侧值列宽度，默认 134；值较长（如型号名）时由调用方调大
function W.kv(parent, x, y, w, name, value, cls, T, val_w)
    val_w = val_w or 134
    W.label(parent, x, y, w - val_w - 4, 20, name, 10, T.text_dim)
    local col = T.text
    if cls == "g" then col = T.green elseif cls == "a" then col = T.amber end
    W.label(parent, x + w - val_w, y, val_w, 20, value, 10.5, col, airui.TEXT_ALIGN_RIGHT)
end

-- 主按钮
function W.btn(parent, x, y, w, h, text, on_click, T)
    return airui.button({
        parent = parent, x = W.d(x), y = W.d(y), w = W.d(w), h = W.d(h),
        text = text, font_size = W.d(12.5),
        style = {
            bg_color = T.accent_soft, border_color = T.cyan, border_width = 1,
            radius = W.d(11), text_color = T.cyan, pressed_bg_color = T.cyan,
        },
        on_click = on_click,
    })
end

return W
