--[[
@module  theme
@summary 软萌马卡龙配色 + 基础控件封装（宠物恒温箱）
@version 1.0
@date    2026.10.28

设计基调：奶油底 + 白卡片 + 大圆角 + 马卡龙点缀色，数字用暖棕，
状态用薄荷绿（正常）/ 珊瑚红（报警），避免纯黑纯白的高对比硬边。
]]
local M = {}

M.C = {
    -- 背景
    bg1    = 0xFFF6EC,
    bg2    = 0xFDEAF2,

    -- 卡片 / 分隔
    bar    = 0xFFFFFF,
    card   = 0xFFFFFF,
    card2  = 0xFFF8F3,
    tile   = 0xFFF4EC,
    line   = 0xFFE4D6,
    line2  = 0xFFCFBC,

    -- 文字
    ink    = 0x4A3B33,
    ink2   = 0x8C786C,
    ink3   = 0xBCA99D,

    -- 马卡龙
    pink   = 0xFF8FB4,
    pink2  = 0xFFE6EF,
    mint   = 0x3FBF9C,
    mint2  = 0xE0F7EF,
    sky    = 0x45B2E6,
    sky2   = 0xE1F3FC,
    lilac  = 0x9184E4,
    lilac2 = 0xEDE8FD,
    butter = 0xFFC03A,
    butter2= 0xFFF3D6,
    coral  = 0xFF8560,
    coral2 = 0xFFEDE5,

    -- 状态
    red    = 0xF2544F,
    red2   = 0xFFE7E5,
    redbg  = 0xFFF6F4,   -- 报警卡片的淡红底
    white  = 0xFFFFFF,
}

M.MCOL = { t = M.C.coral, h = M.C.sky, g = M.C.lilac }
M.MBG  = { t = M.C.coral2, h = M.C.sky2, g = M.C.lilac2 }

local C = M.C

--------------------------------------------------------------------
-- 颜色 / 渐变
--------------------------------------------------------------------
local function chan(c, s) return math.floor(c / s) % 256 end

function M.lerp_color(c1, c2, t)
    local r1, g1, b1 = chan(c1, 65536), chan(c1, 256), chan(c1, 1)
    local r2, g2, b2 = chan(c2, 65536), chan(c2, 256), chan(c2, 1)
    local r = math.floor(r1 + (r2 - r1) * t + 0.5)
    local g = math.floor(g1 + (g2 - g1) * t + 0.5)
    local b = math.floor(b1 + (b2 - b1) * t + 0.5)
    return r * 65536 + g * 256 + b
end

-- airui 无原生渐变，用等高色条堆出来
function M.gradient(parent, x, y, w, h, c1, c2, steps)
    steps = steps or 12
    local sh = math.ceil(h / steps)
    for i = 0, steps - 1 do
        local t = (steps > 1) and (i / (steps - 1)) or 0
        local yy = y + i * sh
        local hh = sh
        if yy + hh > y + h then hh = y + h - yy end
        if hh > 0 then
            airui.container({
                parent = parent, x = x, y = yy, w = w, h = hh,
                color = M.lerp_color(c1, c2, t),
                radius = 0, border_width = 0,
            })
        end
    end
end

--------------------------------------------------------------------
-- 文本宽度估算（用于自动宽度胶囊标签）
--------------------------------------------------------------------
function M.text_width(s, size)
    s = tostring(s or "")
    size = size or 14
    local n, i, len = 0, 1, #s
    while i <= len do
        local b = s:byte(i)
        if b >= 0xF0 then n = n + 2.0; i = i + 4
        elseif b >= 0xE0 then n = n + 1.0; i = i + 3
        elseif b >= 0xC0 then n = n + 0.62; i = i + 2
        else n = n + 0.56; i = i + 1 end
    end
    return math.ceil(n * size) + 2
end

--------------------------------------------------------------------
-- 基础控件
--------------------------------------------------------------------
function M.label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font = "hzfont",
        font_size = size or 14,
        color = color or C.ink,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 在 h 高的槽位里垂直居中（airui label 文字是顶部对齐的，需要手动补偏移）
local function vpad(h, size)
    local py = math.floor((h - size * 1.3) / 2)
    if py < 0 then py = 0 end
    return py
end

function M.label_mid(parent, x, y, w, h, text, size, color, align)
    return M.label(parent, x, y + vpad(h, size), w, size + 8, text, size, color, align)
end

function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opacity or 255,
        radius = radius or 0, border_width = 0,
    })
end

function M.card(parent, x, y, w, h, color, radius, line, lw)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card,
        radius = radius or 22,
        border_color = line or C.line,
        border_width = lw or 2,
    })
end

-- 透明热区（用于承接整块卡片的点击，颜色 opa 1 基本不可见）
function M.hot(parent, x, y, w, h, on_click)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = 0x000000, color_opacity = 1,
        radius = 0, border_width = 0,
        on_click = on_click,
    })
end

function M.button(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font = "hzfont", font_size = size or 16,
        style = {
            bg_color = bg or C.pink, bg_opa = 255,
            text_color = fg or C.white,
            radius = radius or math.floor(h / 2),
            border_width = 0,
            border_color = bg or C.pink,
            pressed_bg_color = C.line2,
            pressed_text_color = C.white,
        },
        on_click = on_click,
    })
end

-- 描边按钮（浅底彩字）
function M.tint_button(parent, x, y, w, h, text, size, bg, fg, on_click, radius, border)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font = "hzfont", font_size = size or 16,
        style = {
            bg_color = bg, bg_opa = 255,
            text_color = fg,
            radius = radius or math.floor(h / 2),
            border_width = 2,
            border_color = border or C.line,
            pressed_bg_color = C.line,
            pressed_text_color = fg,
        },
        on_click = on_click,
    })
end

-- 圆形加减按钮
function M.step_button(parent, x, y, d, text, size, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = d, h = d,
        text = text, font = "hzfont", font_size = size or 20,
        style = {
            bg_color = C.card2, bg_opa = 255,
            text_color = C.ink,
            radius = math.floor(d / 2),
            border_width = 2,
            border_color = C.line,
            pressed_bg_color = C.pink2,
            pressed_text_color = C.pink,
        },
        on_click = on_click,
    })
end

-- 胶囊标签（返回 {box, label}）
function M.pill(parent, x, y, w, h, text, size, bg, fg)
    local box = M.box(parent, x, y, w, h, bg, math.floor(h / 2))
    local lbl = M.label_mid(box, 0, 0, w, h, text, size, fg, airui.TEXT_ALIGN_CENTER)
    return box, lbl
end

--------------------------------------------------------------------
-- Shape
--------------------------------------------------------------------
local function norm(items)
    items = items or {}
    for _, it in ipairs(items) do
        if it.fill then
            if it.color == nil then it.color = it.fill_color or 0xFFFFFF end
            if it.opacity == nil then it.opacity = it.fill_opacity or 255 end
        end
    end
    return items
end

function M.shape(cfg)
    cfg.items = norm(cfg.items)
    return airui.shape(cfg)
end

function M.set_items(sh, items)
    if not sh then return end
    sh:set_items(norm(items))
end

--------------------------------------------------------------------
-- 其它
--------------------------------------------------------------------
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer error", tostring(err)) end
    end, ms or 20)
end

function M.clock_text()
    local t = os.date("*t")
    return string.format("%02d:%02d", t.hour, t.min)
end

function M.date_text()
    local t = os.date("*t")
    local week = { "日", "一", "二", "三", "四", "五", "六" }
    return string.format("%d月%d日 周%s", t.month, t.day, week[t.wday] or "")
end

return M
