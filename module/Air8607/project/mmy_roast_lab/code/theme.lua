--[[
@module  theme
@summary ROAST LAB 设计令牌与通用控件（深焙咖啡配色：炭黑 + 铜 + 奶油）
@version 1.0
@date    2026.10.30
]]
local M = {}

-- ===================== 颜色令牌 =====================
M.C = {
    bg0     = 0x100C0A,   -- 页面底色（上）
    bg1     = 0x1C1410,   -- 页面底色（下）
    panel   = 0x1A1310,   -- 卡片
    panel2  = 0x120D0B,   -- 卡片内嵌块
    panel3  = 0x2A1E18,   -- 高亮块
    line    = 0x2E211A,   -- 分隔线 / 描边
    line2   = 0x4A3427,   -- 强调描边
    ink     = 0xF7EDE2,   -- 主文字（奶油）
    ink2    = 0xC0A490,   -- 次文字
    ink3    = 0x806555,   -- 弱文字

    copper  = 0xC8763C,   -- 品牌主色（铜）
    copper2 = 0xE9A45F,   -- 亮铜 / 高亮数值
    gold    = 0xE8C07D,   -- 一爆标记
    crema   = 0xD9A05B,   -- 咖啡油脂色
    bean    = 0x7A4A2C,   -- 豆色
    green   = 0x7BC96F,   -- 正常
    red     = 0xFF5E52,   -- 报警
    blue    = 0x6FA8DC,   -- 炉温 / 冷色
    violet  = 0xA98BF0,
}

-- 字号档位（刻意收敛为 6 档，控制 hzfont 实例数量）
M.SZ = { xs = 12, s = 14, m = 16, l = 20, xl = 26, hero = 40 }

local ALIGN_LEFT   = airui.TEXT_ALIGN_LEFT
local ALIGN_CENTER = airui.TEXT_ALIGN_CENTER
local ALIGN_RIGHT  = airui.TEXT_ALIGN_RIGHT
M.L, M.CT, M.RT = ALIGN_LEFT, ALIGN_CENTER, ALIGN_RIGHT

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

-- 状态色：ok / warn / danger / info
function M.state_color(level)
    if level == "danger" then return M.C.red end
    if level == "warn" then return M.C.gold end
    if level == "info" then return M.C.blue end
    return M.C.green
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
    })
end

-- 纵向渐变（多条横条拼，暗色场景过渡自然）
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
    local bg = opts.bg or M.C.copper
    local fg = opts.fg or 0x160E0A
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

-- 胶囊标签：返回 {box, label, set(text,color)}
function M.chip(parent, x, y, w, h, text, fg, bg, size)
    size = size or M.SZ.xs
    local box = M.box(parent, x, y, w, h, bg or M.C.panel3, math.floor(h / 2))
    local lb = M.label(parent, x, y, w, h, text, size, fg or M.C.ink2, ALIGN_CENTER)
    return {
        box = box,
        label = lb,
        set = function(t, c, bg)
            if t then pcall(function() lb:set_text(t) end) end
            if c then pcall(function() lb:set_color(c) end) end
            if bg then pcall(function() box:set_color(bg) end) end
        end,
    }
end

-- 分段进度条（container 没有 set_size，用分段点亮实现）
function M.segbar(parent, x, y, w, h, n, color, off_color, gap)
    n = n or 16
    gap = gap or 2
    local sw = math.floor((w - (n - 1) * gap) / n)
    if sw < 1 then sw = 1 end
    local segs = {}
    for i = 1, n do
        segs[i] = M.box(parent, x + (i - 1) * (sw + gap), y, sw, h, off_color or M.C.panel3,
            math.min(2, math.floor(h / 2)))
    end
    local cur = -1
    local bar = { segs = segs, color = color or M.C.copper }
    function bar.set(pct, c)
        pct = math.max(0, math.min(1, pct or 0))
        local lit = math.floor(pct * n + 0.5)
        if lit == cur and (c == nil or c == bar.color) then return end
        cur = lit
        if c then bar.color = c end
        for i = 1, n do
            pcall(function()
                segs[i]:set_color(i <= lit and bar.color or (off_color or M.C.panel3))
            end)
        end
    end
    return bar
end

function M.slider(cfg)
    local ok, obj = pcall(airui.slider, cfg)
    if ok and obj then return obj end
    return nil
end

-- 页面底板：整屏纵向渐变 + 顶部铜色细线
function M.backdrop(parent, w, h)
    w, h = w or 1024, h or 600
    local root = airui.container({ parent = parent, x = 0, y = 0, w = w, h = h, color = M.C.bg1, radius = 0 })
    M.gradient(root, 0, 0, w, h, M.C.bg0, M.C.bg1, 10)
    M.box(root, 0, 0, w, 2, M.C.copper, 0, 70)
    return root
end

function M.hline(parent, x, y, w, color, h)
    return M.box(parent, x, y, w, h or 1, color or M.C.line, 0)
end

-- 顶部小标题（卡片内）
function M.card_head(parent, x, y, w, title, right, right_color)
    M.label(parent, x, y, w, 22, title, M.SZ.m, M.C.ink)
    if right then
        return M.label(parent, x, y, w, 22, right, M.SZ.xs, right_color or M.C.ink3, ALIGN_RIGHT)
    end
end

return M
