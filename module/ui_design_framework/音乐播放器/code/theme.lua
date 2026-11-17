--[[
@module theme
@summary 音乐播放器 HMI —— 双主题配色 / 通用控件 / 页面工厂 / 绘图工具
         设计稿 8603_music/index.html（1024×600，day/night 双主题）
         实机 Air8603 1024×600 RGB 屏

=== 沿用前几个工程的踩坑结论（务必遵守）===
1. label 的 text 在框内【顶部对齐】→ theme.txt 统一下移 y、h 收紧到 size*1.28。
2. 只有 container 有 set_hidden；label/shape/button 没有 → 要整体隐藏就塞进容器。
3. 所有坐标/半径/线宽一律取整；小数坐标会让固件丢弃【整批】图元。
4. 不用 arc / ellipse（本批固件不渲染），弧线一律多段折线拼。
5. 单个 shape 图元 ≤32，超出会吞掉后半段。
6. 动态图元用 set_items 整表重建；shape 范围要盖住整块图形，超出被裁剪。
7. 没有渐变能力：纯色 + 多层低透明度圆/方块近似。
8. 字号下限 16（正文 16~18，数值 20~27，标题 18~20）。
9. 点击回调里销毁/重建子树有 use-after-free 风险（错误被 pcall 吞，表现为
   "点了没反应"）→ 一律 theme.defer(fn)（sys.timerStart(fn, 30)）。
10. 子 label / shape 会拦触摸（"要点两下"）→ 可点区域最后压一层 theme.hit。
11. 部分固件 exwin 没有 bind_root → 必须 if exwin.bind_root then pcall(...) 保护。
12. 切页"先 close 旧窗再 open 新窗"；屏内切换用预建 + set_hidden，不重建。
13. 【禁用 sys.timerLoopStart】固定周期投递会积压 → assert "task event too much"。
    一律 sys.taskInit + sys.wait。
14. 切主题后已建控件颜色不会变 → theme.apply() 就地覆写 C 后整页重建（事件外）。
]]

local sys   = require "sys"
local exwin = require "exwin"
local mock  = require "mock"

local theme = {}

theme.W, theme.H = 1024, 600
pcall(function()
    local w, h = display.getSize()
    if w and h and w > 0 then theme.W = w end
    if h and h > 0 then theme.H = h end
end)

--------------------------------------------------------------------
-- 配色：day（ISA-101 中灰底 + 近白面板）/ night（深石墨）
-- 半透明值已按底色预混合成实色（踩坑：全屏半透明逐像素混合会卡）
--------------------------------------------------------------------
theme.PALETTES = {
    day = {
        bg = 0xDDE2E3, bg2 = 0xF3F5F4, card = 0xF6F8F8, card2 = 0xECEFF0,
        deep = 0xE4E9E9, line = 0xC4CACC, line2 = 0xAAB2B5, mini_border = 0xAAB2B5,
        track = 0xC2C8CA, track2 = 0xC2C8CA, panel = 0xF6F8F8, panel2 = 0xECEFF0,
        btn = 0xF3F5F5, btn2 = 0xF3F5F5, nav = 0xE8EBEC,
        text = 0x1B262C, sub = 0x4F5F67, dim = 0x6C7A82, mini = 0x6C7A82,
        white = 0xFFFFFF, black = 0x000000, red = 0xD93A2B,
        warn = 0xA9542F, bar2 = 0x4E8189,
        shadow = 0xC2C8CA, icon = 0x4F5F67,
        cover_txt = 0xFFFFFF,
        playbg = 0xCE9F69, playfg = 0x141A1F,
        toast_bg = 0x10151A, toast_tx = 0xE7ECEE,
    },
    night = {
        bg = 0x10151A, bg2 = 0x171D23, card = 0x181D21, card2 = 0x13181D,
        deep = 0x0B1014, line = 0x22262B, line2 = 0x393D41, mini_border = 0x4A555C,
        track = 0x262A2E, track2 = 0x4A5056, panel = 0x181D21, panel2 = 0x13181D,
        btn = 0x171C20, btn2 = 0x252C32, nav = 0x0E1317,
        text = 0xE7ECEE, sub = 0x8B979E, dim = 0x5A6870, mini = 0x9AA6AD,
        white = 0xFFFFFF, black = 0x000000, red = 0xE5533D,
        warn = 0xC98A62, bar2 = 0x7E9AA0,
        shadow = 0x05080A, icon = 0x8B979E,
        cover_txt = 0xFFFFFF,
        playbg = 0xC8A26A, playfg = 0x141A1F,
        toast_bg = 0x10151A, toast_tx = 0xE7ECEE,
    },
}

theme.C = {}
theme.mode = "day"      -- day / night（auto 由页面在启动时折算成两者之一）

-- 颜色混合：把 fg 按 a(0~1) 叠到 bg 上，返回实色
function theme.mix(fg, bg, a)
    local r1, g1, b1 = math.floor(fg / 65536) % 256, math.floor(fg / 256) % 256, fg % 256
    local r2, g2, b2 = math.floor(bg / 65536) % 256, math.floor(bg / 256) % 256, bg % 256
    local r = math.floor(r1 * a + r2 * (1 - a) + 0.5)
    local g = math.floor(g1 * a + g2 * (1 - a) + 0.5)
    local b = math.floor(b1 * a + b2 * (1 - a) + 0.5)
    return r * 65536 + g * 256 + b
end

-- 应用主题：就地覆写 theme.C（不换表身份），并把强调色算成派生色
function theme.apply(mode, accent_key)
    theme.mode = (mode == "night") and "night" or "day"
    if accent_key then theme.accent = accent_key end
    local src = theme.PALETTES[theme.mode]
    for k, v in pairs(src) do theme.C[k] = v end

    local ac, key = mock.ACCENTS[1], theme.accent or "amber"
    for i = 1, #mock.ACCENTS do
        if mock.ACCENTS[i].key == key then ac = mock.ACCENTS[i] end
    end
    local C = theme.C
    C.ac = (theme.mode == "day") and ac.day or ac.night
    C.acw = theme.mix(C.ac, C.bg, 0.13)      -- 高亮底色
    C.acline = theme.mix(C.ac, C.bg, 0.34)   -- 高亮描边
    C.glow = theme.mix(C.ac, C.bg, 0.22)
    C.input = (theme.mode == "day") and 0x1B262C or 0xE7ECEE
    C.lum = (theme.mode == "day") and 52 or 63
    return theme.mode
end

function theme.toggle()
    return theme.apply(theme.mode == "day" and "night" or "day", theme.accent)
end

theme.apply("day", "amber")

--------------------------------------------------------------------
-- 事件外执行（踩坑 9）
--------------------------------------------------------------------
function theme.defer(fn, ms)
    if not fn then return end
    sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then
            pcall(log.error, "theme", "defer error: " .. tostring(err))
        end
    end, ms or 30)
end

--------------------------------------------------------------------
-- 中文字宽：中文 1 个字、ASCII 0.55 个字（踩坑：按字节算会多一倍空白）
--------------------------------------------------------------------
function theme.text_w(s, unit)
    s, unit = tostring(s or ""), unit or 1
    local n = 0
    for _, c in utf8.codes(s) do
        n = n + ((c > 0x2E80) and 1 or 0.55)
    end
    return math.floor(n * unit + 0.5)
end

function theme.fmt_time(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

--------------------------------------------------------------------
-- 基础控件
--------------------------------------------------------------------
local C = theme.C

-- 主题就地换色：记录控件对应的 token，切主题时不重建整窗
local color_entries = {}
local function keyof(col)
    if col == nil then return nil end
    for k, v in pairs(C) do
        if v == col then return k end
    end
    return nil
end
local function getter(col)
    local key = keyof(col)
    if key then return function() return C[key] end end
    return function() return col end
end
function theme.register(obj, get, opa, border)
    if not obj then return end
    color_entries[#color_entries + 1] = { obj = obj, get = get, opa = opa, border = border }
end
function theme.clear_registry()
    color_entries = {}
end

function theme.recolor()
    for i = 1, #color_entries do
        local e = color_entries[i]
        local col = e.get()
        if e.border then
            pcall(e.obj.set_border_color, e.obj, col)
        elseif e.opa then
            pcall(e.obj.set_color, e.obj, col, e.opa)
        else
            pcall(e.obj.set_color, e.obj, col)
        end
    end
end

function theme.box(parent, x, y, w, h, color, radius)
    local col = color or C.card
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = col, radius = radius or 0 })
    theme.register(o, getter(col))
    return o
end

function theme.box_a(parent, x, y, w, h, color, radius, opa)
    local col = color or C.card
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = col, color_opacity = opa or 255, radius = radius or 0 })
    theme.register(o, getter(col), opa or 255)
    return o
end

function theme.box_b(parent, x, y, w, h, color, radius, bcol, bw)
    local col = color or C.card
    local bc = bcol or C.line
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = col, radius = radius or 0,
        border_color = bc, border_width = bw or 1 })
    theme.register(o, getter(col))
    theme.register(o, getter(bc), nil, true)
    return o
end

function theme.circle(parent, x, y, d, color, opa)
    local o = airui.container({ parent = parent, x = x, y = y, w = d, h = d,
        color = color, radius = math.floor(d / 2) })
    theme.register(o, getter(color), opa)
    if opa then pcall(o.set_color, o, color, opa) end
    return o
end

function theme.txt(parent, x, y, w, h, text, color, size, align)
    size = size or 16
    local lh = math.floor(size * 1.28 + 0.5)
    local ny = y
    if h and h > lh then ny = y + math.floor((h - lh) / 2) end
    local col = color or C.text
    local o = airui.label({ parent = parent, x = x, y = ny, w = w, h = lh,
        text = text or "", color = col,
        font_size = size, align = align })
    theme.register(o, getter(col))
    return o
end

function theme.icon(parent, x, y, w, h, symbol, color, size)
    local col = color or C.dim
    local o = airui.label({ parent = parent, x = x, y = y, w = w, h = h,
        symbol = symbol, font_size = math.min(size or 20, 24),
        color = col, align = airui.TEXT_ALIGN_CENTER })
    theme.register(o, getter(col))
    return o
end

function theme.hit(parent, x, y, w, h, on_click)
    local o = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = C.bg, radius = 0 })
    pcall(o.set_color, o, C.bg, 0)
    if on_click then pcall(o.set_on_click, o, on_click) end
    return o
end

function theme.shape(parent, x, y, w, h)
    return airui.shape({ parent = parent, x = x, y = y, w = w, h = h, items = {} })
end

-- 胶囊按钮（描边 + 文字 + 热区），返回 { bg, lb, w, h }
function theme.pill(parent, x, y, w, h, text, size, on_click, pri)
    local bc = pri and C.acw or C.btn
    local bdc = pri and C.acline or C.line2
    local bg = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = bc, radius = math.floor(h / 4),
        border_color = bdc, border_width = 1 })
    theme.register(bg, getter(bc))
    theme.register(bg, getter(bdc), nil, true)
    local lb = theme.txt(parent, x, y, w, h, text,
        pri and C.ac or C.sub, size or 16, airui.TEXT_ALIGN_CENTER)
    theme.hit(parent, x, y, w, h, on_click)
    return { bg = bg, lb = lb, w = w, h = h, pri = pri }
end

function theme.pill_on(p)
    pcall(p.bg.set_color, p.bg, C.acw, 255)
    pcall(p.bg.set_border_color, p.bg, C.acline)
    pcall(p.lb.set_color, p.lb, C.ac)
end

function theme.pill_off(p)
    pcall(p.bg.set_color, p.bg, C.btn, 255)
    pcall(p.bg.set_border_color, p.bg, C.line)
    pcall(p.lb.set_color, p.lb, C.dim)
end

--------------------------------------------------------------------
-- 分段控件（对应 html 的 .segs）：等宽小按钮，选中底色换 acw
-- 返回 { items = { {bg, lb}, ... }, set = function(idx) }
--------------------------------------------------------------------
function theme.segs(parent, x, y, w, h, names, cur, on_pick, min_w)
    local n = #names
    local iw = math.floor(w / n)
    if min_w and iw < min_w then iw = min_w end
    local g = { items = {}, on_pick = on_pick }
    for i = 1, n do
        local bx = x + (i - 1) * iw
        local bg = airui.container({ parent = parent, x = bx, y = y, w = iw, h = h,
            color = (i == cur) and C.acw or C.panel2, radius = 0 })
        theme.register(bg, function() return (g.cur == i) and C.acw or C.panel2 end)
        if i < n then
            local sep = airui.container({ parent = parent, x = bx + iw - 1, y = y + 1, w = 1,
                h = h - 2, color = C.line })
            theme.register(sep, function() return C.line end)
        end
        local lb = theme.txt(parent, bx, y, iw, h, names[i],
            (i == cur) and C.ac or C.dim, 16, airui.TEXT_ALIGN_CENTER)
        theme.register(lb, function() return (g.cur == i) and C.ac or C.dim end)
        theme.hit(parent, bx, y, iw, h, function()
            if g.on_pick then g.on_pick(i) end
        end)
        g.items[i] = { bg = bg, lb = lb, x = bx, w = iw }
    end
    g.cur = cur
    function g.set(i)
        if not i or i == g.cur then return end
        g.cur = i
        for k = 1, #g.items do
            local it = g.items[k]
            pcall(it.bg.set_color, it.bg, (k == i) and C.acw or C.panel2, 255)
            pcall(it.lb.set_color, it.lb, (k == i) and C.ac or C.dim)
        end
    end
    return g
end

--------------------------------------------------------------------
-- 开关（44×24，对应 html 的 .sw）
--------------------------------------------------------------------
function theme.switch(parent, x, y, on)
    local track = airui.container({ parent = parent, x = x, y = y, w = 44, h = 24,
        color = on and C.acw or C.track, radius = 12,
        border_color = on and C.acline or C.line2, border_width = 1 })
    local dot = theme.circle(parent, x + (on and 23 or 3), y + 3, 18,
        on and C.ac or C.sub)
    return { track = track, dot = dot, x = x, y = y, on = not not on }
end

function theme.sw_set(sw, on)
    sw.on = not not on
    pcall(sw.track.set_color, sw.track, on and C.acw or C.track, 255)
    pcall(sw.track.set_border_color, sw.track, on and C.acline or C.line2)
    pcall(sw.dot.set_color, sw.dot, on and C.ac or C.sub, 255)
    pcall(sw.dot.set_pos, sw.dot, sw.x + (on and 23 or 3), sw.y + 3)
end

--------------------------------------------------------------------
-- 滑杆：轨道自己画（灰条），slider 本体透明，只负责收手指
-- 注意 radius 同时作用于 indicator 和 knob，必须给 h/2 才是圆旋钮
--------------------------------------------------------------------
function theme.slider(parent, x, y, w, track_h, val, on_change)
    local h = math.max(20, track_h + 12)
    local oy = y + math.floor((track_h - h) / 2)   -- 纵向居中
    return airui.slider({
        parent = parent, x = x, y = oy, w = w, h = h,
        min = 0, max = 100, value = math.floor(val or 0),
        style = {
            bg_opa = 0, indicator_opa = 0, knob_opa = 0,
            border_width = 0, radius = math.floor(h / 2), pad = 6,
        },
        on_change = on_change,
    })
end

--------------------------------------------------------------------
-- 图标（全部 line / circle / rect，width>=1，圆头）
--------------------------------------------------------------------
local IC = {}

-- 圆弧折线（arc/ellipse 实机不渲染，沿用 3D 打印机工程的 ARC 方案）
local function ARC(it, cx, cy, r, a0, a1, col, w)
    local n = math.max(3, math.floor(math.abs(a1 - a0) / 9 + 0.5))
    local px, py
    for i = 0, n do
        local a = math.rad(a0 + (a1 - a0) * i / n)
        local x, y = math.floor(cx + r * math.cos(a)), math.floor(cy + r * math.sin(a))
        if i > 0 then
            it[#it + 1] = { type = "line", x1 = px, y1 = py, x2 = x, y2 = y,
                color = col, width = w, round_start = true, round_end = true }
        end
        px, py = x, y
    end
end

-- 播放三角（实心，用多条矩形叠出来，避免 fill 多边形）
function IC.play(w, h, col)
    local it = {}
    local cx, cy = w / 2, h / 2
    local n = 9
    for i = 1, n do
        local t = (i - 1) / (n - 1)
        local x = math.floor(cx - w * 0.20 + t * w * 0.38)
        local hh = math.floor(h * (0.70 - t * 0.54))
        if hh > 0 then
            it[#it + 1] = { type = "rect", x = x - 2, y = math.floor(cy - hh / 2),
                w = 4, h = hh, radius = 0, color = col, width = 1,
                fill = true, fill_color = col, fill_opacity = 255 }
        end
    end
    return it
end

function IC.pause(w, h, col)
    local bw = math.floor(w * 0.14)
    local bh = math.floor(h * 0.5)
    return {
        { type = "rect", x = math.floor(w / 2 - bw * 2), y = math.floor((h - bh) / 2),
          w = bw, h = bh, radius = 1, color = col, width = 1,
          fill = true, fill_color = col, fill_opacity = 255 },
        { type = "rect", x = math.floor(w / 2 + bw), y = math.floor((h - bh) / 2),
          w = bw, h = bh, radius = 1, color = col, width = 1,
          fill = true, fill_color = col, fill_opacity = 255 },
    }
end

function IC.prev(w, h, col)
    local cy = math.floor(h / 2)
    return {
        { type = "rect", x = math.floor(w * 0.22), y = cy - 8, w = 3, h = 16,
          radius = 1, color = col, width = 1, fill = true,
          fill_color = col, fill_opacity = 255 },
        { type = "line", x1 = math.floor(w * 0.76), y1 = cy - 8,
          x2 = math.floor(w * 0.40), y2 = cy,
          color = col, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = math.floor(w * 0.40), y1 = cy,
          x2 = math.floor(w * 0.76), y2 = cy + 8,
          color = col, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = math.floor(w * 0.76), y1 = cy + 8,
          x2 = math.floor(w * 0.76), y2 = cy - 8,
          color = col, width = 3, round_start = true, round_end = true },
    }
end

function IC.next(w, h, col)
    local cy = math.floor(h / 2)
    return {
        { type = "rect", x = math.floor(w * 0.72), y = cy - 8, w = 3, h = 16,
          radius = 1, color = col, width = 1, fill = true,
          fill_color = col, fill_opacity = 255 },
        { type = "line", x1 = math.floor(w * 0.24), y1 = cy - 8,
          x2 = math.floor(w * 0.60), y2 = cy,
          color = col, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = math.floor(w * 0.60), y1 = cy,
          x2 = math.floor(w * 0.24), y2 = cy + 8,
          color = col, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = math.floor(w * 0.24), y1 = cy + 8,
          x2 = math.floor(w * 0.24), y2 = cy - 8,
          color = col, width = 3, round_start = true, round_end = true },
    }
end

-- 心形：两段折线拼 V 形 + 两个圆（不用 arc）
function IC.heart(w, h, col, solid)
    local sx, sy = w / 24, h / 24
    local function pt(x, y)
        return math.floor(x * sx), math.floor(y * sy)
    end
    local it = {}
    if solid then
        local r = math.max(2, math.floor(4 * sx))
        local lx, ly = pt(8, 8)
        local rx, ry = pt(16, 8)
        it[1] = { type = "circle", cx = lx, cy = ly, r = r, color = col,
            width = 1, fill = true, fill_color = col, fill_opacity = 255 }
        it[2] = { type = "circle", cx = rx, cy = ry, r = r, color = col,
            width = 1, fill = true, fill_color = col, fill_opacity = 255 }
        for i = 0, 11 do
            local y = 10 + i * 0.9
            local half = 8 - i * 0.62
            local x, py = pt(12 - half, y)
            local bw = math.max(2, math.floor(half * 2 * sx))
            local bh = math.max(1, math.floor(2 * sy))
            it[#it + 1] = { type = "rect", x = x, y = py, w = bw, h = bh,
                radius = 0, color = col, width = 1,
                fill = true, fill_color = col, fill_opacity = 255 }
        end
        return it
    end
    local function arc(cx, cy, r, a0, a1, steps)
        local px, py
        for i = 0, steps do
            local a = math.rad(a0 + (a1 - a0) * i / steps)
            local x, y = pt(cx + math.cos(a) * r, cy + math.sin(a) * r)
            if i > 0 then
                it[#it + 1] = { type = "line", x1 = px, y1 = py, x2 = x, y2 = y,
                    color = col, width = 2, round_start = true, round_end = true }
            end
            px, py = x, y
        end
    end
    arc(8, 8, 4, 0, -180, 7)
    local x1, y1 = pt(4, 8)
    local x2, y2 = pt(12, 20)
    local x3, y3 = pt(20, 8)
    it[#it + 1] = { type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
        color = col, width = 2, round_start = true, round_end = true }
    it[#it + 1] = { type = "line", x1 = x2, y1 = y2, x2 = x3, y2 = y3,
        color = col, width = 2, round_start = true, round_end = true }
    arc(16, 8, 4, 360, 180, 7)
    return it
end

-- 星标：四条折线拼五角星轮廓（实心用粗线近似）
function IC.star(w, h, col, solid)
    local pts = {}
    local cx, cy = w / 2, h / 2
    local r1, r2 = w * 0.46, w * 0.19
    for i = 0, 9 do
        local ang = -math.pi / 2 + i * math.pi / 5
        local r = (i % 2 == 0) and r1 or r2
        pts[#pts + 1] = { cx + math.cos(ang) * r, cy + math.sin(ang) * r }
    end
    local it = {}
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        it[#it + 1] = { type = "line", x1 = math.floor(a[1]), y1 = math.floor(a[2]),
            x2 = math.floor(b[1]), y2 = math.floor(b[2]),
            color = col, width = solid and 5 or 2,
            round_start = true, round_end = true }
    end
    return it
end

-- 太阳 / 月亮（对应 html 的 i-sun / i-moon，线稿，不用实心圆）
function IC.sun(w, h, col)
    local cx, cy = math.floor(w / 2), math.floor(h / 2)
    local it = {
        { type = "circle", cx = cx, cy = cy, r = math.max(2, math.floor(w * 4 / 24)),
          color = col, width = 1, fill = true, fill_color = col, fill_opacity = 255 },
    }
    local r1, r2 = w * 7 / 24, w * 10 / 24
    for i = 0, 7 do
        local ang = math.rad(i * 45)
        it[#it + 1] = { type = "line",
            x1 = math.floor(cx + math.cos(ang) * r1), y1 = math.floor(cy + math.sin(ang) * r1),
            x2 = math.floor(cx + math.cos(ang) * r2), y2 = math.floor(cy + math.sin(ang) * r2),
            color = col, width = 2, round_start = true, round_end = true }
    end
    return it
end

function IC.moon(w, h, col)
    -- 弯月：外弧 + 内弧，全部折线（对应 "M20 14.5 A8.5... z"）
    local it = {}
    ARC(it, w * 50 / 100, h * 50 / 100, w * 35 / 100, 15, 255, col, 2)
    ARC(it, w * 58 / 100, h * 42 / 100, w * 35 / 100, 255, 15, col, 2)
    return it
end

-- 蓝牙（顶栏：html path M7 7l10 10-5 4V3l5 4L7 17）
function IC.bt(w, h, col)
    local x = function(v) return math.floor(w * v / 24) end
    local y = function(v) return math.floor(h * v / 24) end
    return {
        { type = "line", x1 = x(7), y1 = y(7), x2 = x(17), y2 = y(17), color = col,
          width = 2, round_start = true, round_end = true },
        { type = "line", x1 = x(17), y1 = y(17), x2 = x(12), y2 = y(21), color = col,
          width = 2, round_start = true, round_end = true },
        { type = "line", x1 = x(12), y1 = y(21), x2 = x(12), y2 = y(3), color = col,
          width = 2, round_start = true, round_end = true },
        { type = "line", x1 = x(12), y1 = y(3), x2 = x(17), y2 = y(7), color = col,
          width = 2, round_start = true, round_end = true },
        { type = "line", x1 = x(17), y1 = y(7), x2 = x(7), y2 = y(17), color = col,
          width = 2, round_start = true, round_end = true },
    }
end

-- WiFi（四段弧线 + 底部点；弧线用折线近似）
function IC.wifi(w, h, col)
    local cx = math.floor(w / 2)
    local cy = math.floor(h * 0.80)
    local it = {
        { type = "circle", cx = cx, cy = math.floor(h * 0.87),
          r = math.max(2, math.floor(w / 24)), color = col, width = 1,
          fill = true, fill_color = col, fill_opacity = 255 },
    }
    local function arc(r)
        local px, py
        for i = 0, 8 do
            local a = math.rad(200 + 140 * i / 8)
            local x = math.floor(cx + math.cos(a) * r)
            local y = math.floor(cy + math.sin(a) * r)
            if i > 0 then
                it[#it + 1] = { type = "line", x1 = px, y1 = py, x2 = x, y2 = y,
                    color = col, width = 2, round_start = true, round_end = true }
            end
            px, py = x, y
        end
    end
    arc(w * 0.40)
    arc(w * 0.29)
    arc(w * 0.18)
    return it
end

-- 导航①：音符（path + 两个圆）
function IC.note(w, h, col)
    local x = function(v) return math.floor(w * v / 24) end
    local y = function(v) return math.floor(h * v / 24) end
    return {
        { type = "line", x1 = x(9), y1 = y(18), x2 = x(9), y2 = y(6), color = col,
          width = 2, round_start = true, round_end = true },
        { type = "line", x1 = x(9), y1 = y(6), x2 = x(19), y2 = y(4), color = col,
          width = 2, round_start = true, round_end = true },
        { type = "line", x1 = x(19), y1 = y(4), x2 = x(19), y2 = y(16), color = col,
          width = 2, round_start = true, round_end = true },
        { type = "circle", cx = x(6), cy = y(18), r = math.max(2, math.floor(w * 2.5 / 24)),
          color = col, width = 2, fill = false, fill_color = col, fill_opacity = 0 },
        { type = "circle", cx = x(16), cy = y(16), r = math.max(2, math.floor(w * 2.5 / 24)),
          color = col, width = 2, fill = false, fill_color = col, fill_opacity = 0 },
    }
end

-- 导航④：齿轮（圆 r3 + 8 辐条）
function IC.gear(w, h, col)
    local cx, cy = math.floor(w / 2), math.floor(h / 2)
    local it = {
        { type = "circle", cx = cx, cy = cy,
          r = math.max(2, math.floor(w * 3 / 24)), color = col,
          width = 1, fill = true, fill_color = col, fill_opacity = 255 },
    }
    for i = 0, 7 do
        local a = math.rad(i * 45)
        it[#it + 1] = { type = "line",
            x1 = math.floor(cx + math.cos(a) * w * 7 / 24),
            y1 = math.floor(cy + math.sin(a) * h * 7 / 24),
            x2 = math.floor(cx + math.cos(a) * w * 9.5 / 24),
            y2 = math.floor(cy + math.sin(a) * h * 9.5 / 24),
            color = col, width = 2, round_start = true, round_end = true }
    end
    return it
end

-- 搜索放大镜（曲库输入框）
function IC.search(w, h, col)
    return {
        { type = "circle", cx = math.floor(w * 10.5 / 24), cy = math.floor(h * 10.5 / 24),
          r = math.floor(w * 6.5 / 24), color = col, width = 2,
          fill = false, fill_color = col, fill_opacity = 0 },
        { type = "line", x1 = math.floor(w * 15.5 / 24), y1 = math.floor(h * 15.5 / 24),
          x2 = math.floor(w * 21 / 24), y2 = math.floor(h * 21 / 24),
          color = col, width = 2, round_start = true, round_end = true },
    }
end

-- 音量喇叭 + 两条弧（对应 html 的 vol svg）
function IC.vol(w, h, col)
    local x = function(v) return math.floor(w * v / 24) end
    local y = function(v) return math.floor(h * v / 24) end
    local it = {
        { type = "line", x1 = x(4), y1 = y(9), x2 = x(4), y2 = y(15), color = col, width = 2 },
        { type = "line", x1 = x(4), y1 = y(15), x2 = x(8), y2 = y(15), color = col, width = 2 },
        { type = "line", x1 = x(8), y1 = y(15), x2 = x(13), y2 = y(19), color = col, width = 2 },
        { type = "line", x1 = x(13), y1 = y(19), x2 = x(13), y2 = y(5), color = col, width = 2 },
        { type = "line", x1 = x(13), y1 = y(5), x2 = x(8), y2 = y(9), color = col, width = 2 },
        { type = "line", x1 = x(8), y1 = y(9), x2 = x(4), y2 = y(9), color = col, width = 2 },
    }
    ARC(it, x(16), y(12), x(4), 310, 410, col, 2)
    ARC(it, x(19), y(12), x(7), 310, 410, col, 2)
    return it
end

theme.IC = IC

--------------------------------------------------------------------
-- 页面工厂（单 exwin 页，页内预建多屏 + set_hidden）
-- build_fn(root) 返回 { update, interval, rebuild }
--------------------------------------------------------------------
local current_win, current_root = nil, nil

function theme.open(build_fn)
    if current_win then
        local w = current_win
        current_win = nil
        pcall(exwin.close, w)                 -- 踩坑 12：先关旧窗
    end
    current_win = exwin.open({
        on_create = function()
            theme.clear_registry()
            current_root = airui.container({ parent = airui.screen, x = 0, y = 0,
                w = theme.W, h = theme.H, color = theme.C.bg })
            theme.register(current_root, function() return theme.C.bg end)
            build_fn(current_root)
            if exwin.bind_root then pcall(exwin.bind_root, current_root) end
        end,
        on_destroy = function()
            if current_root then pcall(current_root.destroy, current_root) end
            current_root = nil
        end,
    })
    return current_win
end

function theme.close()
    if current_win then
        local w = current_win
        current_win = nil
        pcall(exwin.close, w)
    end
end

return theme
