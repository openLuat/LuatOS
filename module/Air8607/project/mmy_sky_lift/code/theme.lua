--[[
@module  theme
@summary SkyLift 设计令牌与通用控件封装（极夜雪山配色）
@version 1.0
@date    2026.11.06
]]
local M = {}

-- ===================== 颜色令牌 =====================
M.C = {
    bg0     = 0x050A12,   -- 页面底色（上）
    bg1     = 0x0A1422,   -- 页面底色（下）
    panel   = 0x0D1929,   -- 卡片
    panel2  = 0x122234,   -- 卡片内嵌块
    panel3  = 0x1B3047,   -- 高亮块
    line    = 0x1C2F45,   -- 分隔线 / 卡片描边
    line2   = 0x2C4A67,   -- 强调描边
    ink     = 0xE9F3FF,   -- 主文字
    ink2    = 0x93AECE,   -- 次文字
    ink3    = 0x5A7695,   -- 弱文字
    ice     = 0x4FE3D8,   -- 品牌主色（冰湖青）
    snow    = 0xE8F4FF,   -- 雪白
    blue    = 0x8FB8FF,   -- 冰蓝
    violet  = 0xA98BF0,   -- 极光紫
    gold    = 0xFFC24B,   -- 警示金
    amber   = 0xFF8A4B,   -- 暖橙
    green   = 0x49E0A0,   -- 正常
    red     = 0xFF5A6A,   -- 报警
    night   = 0x081221,   -- 夜空
    ridge   = 0x16283C,   -- 远山
    ridge2  = 0x1E3A52,   -- 近山
    powder  = 0x2A4A63,   -- 雪面
}

-- 字号档位（刻意收敛为 6 档，控制 hzfont 实例数量）
M.SZ = { xs = 12, s = 14, m = 16, l = 20, xl = 26, hero = 40 }

local ALIGN_LEFT   = airui.TEXT_ALIGN_LEFT
local ALIGN_CENTER = airui.TEXT_ALIGN_CENTER
local ALIGN_RIGHT  = airui.TEXT_ALIGN_RIGHT

-- ===================== 数值工具 =====================
-- string.format("%d", x) 在 Lua 5.4 下遇到浮点会直接抛错
-- （bad argument #2 to 'format' (number has no integer representation)），
-- 凡是送进 %d 的量都要先过一遍 M.n() 取整
function M.n(v)
    local x = tonumber(v)
    if not x then return 0 end
    if x >= 0 then return math.floor(x + 0.5) end
    return -math.floor(-x + 0.5)
end

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
    if level == "danger" then return "报警" end
    if level == "warn" then return "关注" end
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
    local bg = opts.bg or M.C.ice
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

-- 分段进度条（container 没有 set_size，用 LED 分段实现，视觉上也更像雪深刻度）
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
    local bar = { segs = segs, color = color or M.C.ice }
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
    local root = airui.container({ parent = parent, x = 0, y = 0, w = 1024, h = 600, color = M.C.bg1, radius = 0 })
    M.gradient(root, 0, 0, 1024, 600, M.C.bg0, M.C.bg1, 8)
    M.box(root, 0, 0, 1024, 2, M.C.ice, 0, 40)
    return root
end

function M.hline(parent, x, y, w, color, h)
    return M.box(parent, x, y, w, h or 1, color or M.C.line, 0)
end

function M.vline(parent, x, y, h, color)
    return M.box(parent, x, y, 1, h, color or M.C.line, 0)
end

-- 按字符截断（中文按字计），超长补省略号
local has_utf8 = (type(utf8) == "table" and utf8.len ~= nil)
function M.fit(text, n)
    if not text or text == "" then return "" end
    if not has_utf8 then
        if #text > n * 3 then return string.sub(text, 1, n * 3 - 3) .. "..." end
        return text
    end
    local len = utf8.len(text)
    if not len or len <= n then return text end
    local cut = utf8.offset(text, n + 1)
    if not cut then return text end
    return string.sub(text, 1, cut - 1) .. "…"
end

function M.align_left() return ALIGN_LEFT end
function M.align_center() return ALIGN_CENTER end
function M.align_right() return ALIGN_RIGHT end

return M
