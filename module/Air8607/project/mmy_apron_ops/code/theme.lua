--[[
@module  theme
@summary AeroDeck 设计令牌与通用控件封装（夜航机坪配色）
@version 1.0
@date    2026.11.05
]]
local conf = require "conf"

local M = {}

-- ===================== 颜色令牌 =====================
M.C = {
    bg0     = 0x04070E,   -- 页面底色（上）
    bg1     = 0x0A1220,   -- 页面底色（下）
    panel   = 0x0C1626,   -- 卡片
    panel2  = 0x111F33,   -- 卡片内嵌块
    panel3  = 0x1A2C46,   -- 高亮块
    line    = 0x1A2A40,   -- 分隔线 / 卡片描边
    line2   = 0x2A4A6B,   -- 强调描边
    ink     = 0xE9F1FA,   -- 主文字
    ink2    = 0x93A9C4,   -- 次文字
    ink3    = 0x5A7291,   -- 弱文字
    cyan    = 0x36D6E8,   -- 雷达青（品牌主色）
    amber   = 0xFFB648,   -- 琥珀（滑行道灯 / 强调）
    gold    = 0xFFB648,   -- 警示金
    green   = 0x37D99A,   -- 正常 / 放行
    red     = 0xFF5C6E,   -- 报警
    blue    = 0x4E9BFF,   -- 蓝
    violet  = 0x9B7BF0,   -- 紫（配餐/服务）
    orange  = 0xFF7A45,   -- 橙（除冰）
    taxi    = 0x16283C,   -- 滑行道底色
    land    = 0x0E1B2B,   -- 停机坪底色
}

-- 字号档位（刻意收敛为 6 档，控制 hzfont 实例数量）
M.SZ = { xs = 12, s = 14, m = 16, l = 20, xl = 26, hero = 40 }

local ALIGN_LEFT   = airui.TEXT_ALIGN_LEFT
local ALIGN_CENTER = airui.TEXT_ALIGN_CENTER
local ALIGN_RIGHT  = airui.TEXT_ALIGN_RIGHT

-- ===================== 颜色工具 =====================
local function split(c)
    return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
end

function M.mix(c1, c2, t)
    if t <= 0 then return c1 end
    if t >= 1 then return c2 end
    local r1, g1, b1 = split(c1)
    local r2, g2, b2 = split(c2)
    local r = math.floor(r1 + (r2 - r1) * t + 0.5)
    local g = math.floor(g1 + (g2 - g1) * t + 0.5)
    local b = math.floor(b1 + (b2 - b1) * t + 0.5)
    return r * 65536 + g * 256 + b
end

-- 加权混色，list = { {color, weight}, ... }
function M.blend(list)
    local r, g, b, sum = 0, 0, 0, 0
    for _, it in ipairs(list) do
        local w = it[2] or 0
        if w > 0 then
            local cr, cg, cb = split(it[1])
            r = r + cr * w
            g = g + cg * w
            b = b + cb * w
            sum = sum + w
        end
    end
    if sum <= 0 then return 0x000000 end
    return math.floor(r / sum + 0.5) * 65536 + math.floor(g / sum + 0.5) * 256 + math.floor(b / sum + 0.5)
end

-- 状态色：ok / warn / danger
function M.state_color(level)
    if level == "danger" then return M.C.red end
    if level == "warn" then return M.C.gold end
    return M.C.green
end

function M.state_text(level)
    if level == "danger" then return "超限" end
    if level == "warn" then return "偏离" end
    return "正常"
end

-- ===================== 基础控件 =====================
function M.label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font_size = size or M.SZ.s,
        color = color or M.C.ink,
        align = align or ALIGN_LEFT,
    })
end

function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, radius = radius or 0, color_opacity = opacity,
    })
end

function M.card(parent, x, y, w, h, opts)
    opts = opts or {}
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = opts.color or M.C.panel,
        color_opacity = opts.opacity,
        radius = opts.radius or 12,
        border_color = opts.border_color or M.C.line,
        border_width = opts.border_width or 1,
        on_click = opts.on_click,
        on_long_press = opts.on_long_press,
    })
end

-- 纵向渐变（用多条 1px 块拼，暗色场景下过渡自然）
function M.gradient(parent, x, y, w, h, c1, c2, steps)
    steps = steps or 10
    local sh = math.ceil(h / steps)
    local list = {}
    for i = 1, steps do
        local t = (i - 1) / math.max(steps - 1, 1)
        local hh = sh
        if i == steps then hh = y + h - (y + (i - 1) * sh) end
        if hh > 0 then
            list[#list + 1] = M.box(parent, x, y + (i - 1) * sh, w, hh, M.mix(c1, c2, t), 0)
        end
    end
    return list
end

function M.shape(parent, x, y, w, h, items)
    return airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = items })
end

function M.button(parent, x, y, w, h, text, opts)
    opts = opts or {}
    local bg = opts.bg or M.C.cyan
    local fg = opts.fg or M.C.bg0
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text,
        font_size = opts.size or M.SZ.s,
        on_click = opts.on_click,
        style = {
            bg_color = bg,
            bg_opa = opts.bg_opa or 255,
            border_color = opts.border or bg,
            border_width = opts.border_width or 0,
            radius = opts.radius or 9,
            pad = 0,
            text_color = fg,
            pressed_bg_color = opts.pressed or M.mix(bg, M.C.ink, 0.28),
            pressed_bg_opa = 255,
            pressed_text_color = fg,
            focus_outline_width = 0,
        },
    })
end

-- 描边按钮（次级操作）
function M.ghost(parent, x, y, w, h, text, opts)
    opts = opts or {}
    return M.button(parent, x, y, w, h, text, {
        bg = opts.bg or M.C.panel2,
        fg = opts.fg or M.C.ink,
        border = opts.border or M.C.line2,
        border_width = 1,
        pressed = M.C.panel3,
        size = opts.size,
        on_click = opts.on_click,
        radius = opts.radius,
    })
end

-- 胶囊标签：返回 {box=..., label=..., set=function(text,color)}
function M.chip(parent, x, y, w, h, text, fg, bg, size, opacity)
    size = size or M.SZ.xs
    local box = M.box(parent, x, y, w, h, bg or M.C.panel2, math.floor(h / 2), opacity)
    local lb = M.label(parent, x, y, w, h, text, size, fg or M.C.ink2, ALIGN_CENTER)
    return {
        box = box,
        label = lb,
        set = function(t, c)
            if t then lb:set_text(t) end
            if c then lb:set_color(c) end
        end,
    }
end

-- 分段进度条（container 没有 set_size，用 LED 分段实现，视觉上也像跑道灯）
-- 返回 {set=function(pct 0~1, color)}
function M.segbar(parent, x, y, w, h, n, color, off_color, gap)
    n = n or 16
    gap = gap or 2
    local sw = math.floor((w - (n - 1) * gap) / n)
    if sw < 1 then sw = 1 end
    local segs = {}
    for i = 1, n do
        segs[i] = M.box(parent, x + (i - 1) * (sw + gap), y, sw, h, off_color or M.C.panel3, math.min(2, math.floor(h / 2)))
    end
    local cur = -1
    local bar = { segs = segs, color = color or M.C.cyan }
    function bar.set(pct, c)
        pct = math.max(0, math.min(1, pct or 0))
        local lit = math.floor(pct * n + 0.5)
        if lit == cur and (c == nil or c == bar.color) then return end
        cur = lit
        if c then bar.color = c end
        for i = 1, n do
            if i <= lit then
                segs[i]:set_color(bar.color)
            else
                segs[i]:set_color(off_color or M.C.panel3)
            end
        end
    end
    return bar
end

function M.slider(cfg)
    local ok, obj = pcall(airui.slider, cfg)
    if ok and obj then return obj end
    return nil
end

-- 页面底板：整屏纵向渐变 + 顶部微光
function M.backdrop(parent)
    local root = airui.container({ parent = parent, x = 0, y = 0, w = conf.W, h = conf.H,
        color = M.C.bg1, radius = 0 })
    M.gradient(root, 0, 0, conf.W, conf.H, M.C.bg0, M.C.bg1, 8)
    M.box(root, 0, 0, conf.W, 2, M.C.cyan, 0, 46)
    return root
end

-- 分隔线
function M.hline(parent, x, y, w, color, h)
    return M.box(parent, x, y, w, h or 1, color or M.C.line, 0)
end

function M.vline(parent, x, y, h, color)
    return M.box(parent, x, y, 1, h, color or M.C.line, 0)
end

return M
