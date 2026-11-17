--[[
@module  theme
@summary IMM-6 设计令牌与通用控件（石墨灰 + 通电青 + 安全琥珀）
@version 1.0
@date    2026.11.15
]]
local M = {}

-- ===================== 颜色令牌 =====================
M.C = {
    bg0      = 0x0A0C10,   -- 页面底色（上）
    bg1      = 0x101318,   -- 页面底色（下）
    panel    = 0x15181E,   -- 卡片
    panel2   = 0x1C2028,   -- 卡片内嵌块
    panel3   = 0x262B35,   -- 高亮块 / 轨道
    line     = 0x2A303B,   -- 分隔线 / 卡片描边
    line2    = 0x3E4655,   -- 强调描边
    ink      = 0xE9ECF1,   -- 主文字
    ink2     = 0x98A2B3,   -- 次文字
    ink3     = 0x626C7D,   -- 弱文字
    run      = 0x2FD9C5,   -- 通电青（品牌主色 / 运行 / 导通）
    amber    = 0xFFB020,   -- 安全琥珀（设定值 / 注意）
    ice      = 0x5AC8FA,   -- 实测数据
    green    = 0x4ADE80,   -- 正常
    red      = 0xFF4D5E,   -- 报警
    violet   = 0x9B8CFF,   -- 保压 / 机械手
    teal     = 0x1FA3A3,   -- 辅助青
    steel    = 0x39414F,   -- 结构件
    steel2   = 0x4C5566,   -- 结构件高光
    melt     = 0xFF8A3D,   -- 熔料橙
}

-- 字号档位（收敛为 6 档，控制 hzfont 实例数量）
M.SZ = { xs = 12, s = 14, m = 16, l = 20, xl = 26, hero = 40 }

local ALIGN_LEFT   = airui.TEXT_ALIGN_LEFT
local ALIGN_CENTER = airui.TEXT_ALIGN_CENTER
local ALIGN_RIGHT  = airui.TEXT_ALIGN_RIGHT

-- ===================== 数值工具 =====================
-- string.format("%d", x) 在 Lua 5.4 下遇到浮点会直接抛错，
-- 凡是要送进 %d 的量都先过一遍 M.n()
function M.n(v)
    local x = tonumber(v)
    if not x then return 0 end
    if x >= 0 then return math.floor(x + 0.5) end
    return -math.floor(-x + 0.5)
end

function M.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
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

function M.alpha(color, k)
    return M.mix(M.C.bg0, color, k)
end

-- 状态色：ok / warn / danger
function M.state_color(level)
    if level == "danger" then return M.C.red end
    if level == "warn" then return M.C.amber end
    return M.C.green
end

function M.state_text(level)
    if level == "danger" then return "报警" end
    if level == "warn" then return "关注" end
    return "正常"
end

-- 温度偏差 → 颜色：带内青，越带宽琥珀，超联锁红
function M.deviation_color(d, band)
    band = band or 3
    local a = math.abs(d)
    if a <= band then return M.C.run end
    if a <= band * 1.8 then return M.C.amber end
    return M.C.red
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
        radius = opts.radius or 8,
        border_color = opts.border_color or M.C.line,
        border_width = opts.border_width or 1,
        on_click = opts.on_click,
        on_long_press = opts.on_long_press,
    })
end

-- 卡片标题：左侧一根 3px 竖条 + 标题 + 可选右侧说明
function M.title(card, x, y, w, text, right_text, right_color)
    M.box(card, x, y + 3, 3, 13, M.C.run, 1)
    M.label(card, x + 9, y, w - 9, 18, text, M.SZ.s, M.C.ink)
    if right_text then
        M.label(card, x + 9, y, w - 9, 18, right_text, M.SZ.xs,
            right_color or M.C.ink3, ALIGN_RIGHT)
    end
end

-- 纵向渐变：多条等高分块，最后一块补齐余量
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
    local bg = opts.bg or M.C.run
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
            radius = opts.radius or 6,
            pad = 0,
            text_color = fg,
            pressed_bg_color = opts.pressed or M.mix(bg, M.C.ink, 0.24),
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

-- 胶囊标签：返回 { box, label, set(text,fg,bg) }
-- set 内部缓存上一次的值，值没变就不写 LVGL，避免每秒无谓重绘
function M.chip(parent, x, y, w, h, text, fg, bg, size, opacity)
    size = size or M.SZ.xs
    local box = M.box(parent, x, y, w, h, bg or M.C.panel2, math.floor(h / 3), opacity)
    local lb = M.label(parent, x, y, w, h, text, size, fg or M.C.ink2, ALIGN_CENTER)
    local last = { t = text, c = fg, bg = bg }
    return {
        box = box,
        label = lb,
        set = function(t, c, b)
            if t and last.t ~= t then
                last.t = t
                lb:set_text(t)
            end
            if c and last.c ~= c then
                last.c = c
                lb:set_color(c)
            end
            if b and last.bg ~= b then
                last.bg = b
                pcall(function() box:set_color(b) end)
            end
        end,
    }
end

-- 进度条（原生 bar，高度决定轨道粗细）
function M.bar(parent, x, y, w, h, value, color, track, radius)
    local ok, obj = pcall(airui.bar, {
        parent = parent, x = x, y = y, w = w, h = h,
        min = 0, max = 100, value = M.n(M.clamp(value or 0, 0, 100)),
        bg_color = track or M.C.panel3,
        indicator_color = color or M.C.run,
        border_width = 0,
        radius = radius or math.floor(h / 2),
    })
    if ok then return obj end
    return nil
end

-- bar:set_value 只接受整数，浮点会触发 Lua 5.4 的 no integer representation
function M.setbar(bar, v, anim)
    if not bar then return end
    pcall(function()
        bar:set_value(M.n(M.clamp(v or 0, 0, 100)), anim and true or false)
    end)
end

function M.setbar_color(bar, color)
    if not bar then return end
    pcall(function() bar:set_indicator_color(color) end)
end

-- 分段刻度条：固定小方块，靠改颜色点亮（container 没有 set_size，做不了伸缩条）
function M.segbar(parent, x, y, w, h, n, color, off_color, gap)
    n = n or 16
    gap = gap or 2
    local sw = math.floor((w - (n - 1) * gap) / n)
    if sw < 1 then sw = 1 end
    local segs = {}
    for i = 1, n do
        segs[i] = M.box(parent, x + (i - 1) * (sw + gap), y, sw, h,
            off_color or M.C.panel3, math.min(2, math.floor(h / 2)))
    end
    local cur = -1
    local bar = { segs = segs, color = color or M.C.run, n = n }
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

-- 页面底板：整屏纵向渐变 + 顶部一线通电青
function M.backdrop(parent)
    local root = airui.container({ parent = parent, x = 0, y = 0, w = 1024, h = 600, color = M.C.bg1, radius = 0 })
    M.gradient(root, 0, 0, 1024, 600, M.C.bg0, M.C.bg1, 12)
    M.box(root, 0, 0, 1024, 2, M.C.run, 0, 36)
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

-- ===================== 工业小件 =====================
-- 状态灯：外圈暗环 + 内芯，返回 { box, set(color) }
function M.led(parent, x, y, size, color)
    local box = M.box(parent, x, y, size, size, color or M.C.ink3, math.floor(size / 2))
    local last = color
    return {
        box = box,
        set = function(c)
            if c and c ~= last then
                last = c
                pcall(function() box:set_color(c) end)
            end
        end,
    }
end

-- 位号徽标：等宽感的小方块，用于 I0.0 / Q0.1 / M0.0
function M.tag(parent, x, y, w, text, color, bg)
    local box = M.box(parent, x, y, w, 16, bg or M.C.panel2, 3)
    local lb = M.label(parent, x, y, w, 16, text, M.SZ.xs, color or M.C.ink2, ALIGN_CENTER)
    return { box = box, label = lb }
end

-- 指标块：标签 / 大值 / 单位
function M.metric(parent, x, y, w, cap, unit, size)
    local lb = M.label(parent, x, y, w, 16, cap, M.SZ.xs, M.C.ink3)
    local val = M.label(parent, x, y + 16, w - 24, 26, "--", size or M.SZ.l, M.C.ink)
    local un = M.label(parent, x, y + 24, w, 16, unit or "", M.SZ.xs, M.C.ink3, ALIGN_RIGHT)
    return { cap = lb, val = val, unit = un }
end

-- 带轨道的读数行：左标签、右数值、下方细条
function M.rowbar(parent, x, y, w, cap, color)
    local lb = M.label(parent, x, y, w - 76, 16, cap, M.SZ.xs, M.C.ink3)
    local val = M.label(parent, x + w - 90, y - 2, 90, 18, "--", M.SZ.s, M.C.ink, ALIGN_RIGHT)
    local bar = M.bar(parent, x, y + 18, w, 4, 0, color or M.C.run, M.C.panel3)
    return { cap = lb, val = val, bar = bar }
end

return M
