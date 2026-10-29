--[[
@module  theme
@summary 深空调色板 + 基础控件封装（深空蓝黑 + 星野青，支持夜视红光模式）
@version 1.0
@date    2026.10.28
]]
local M = {}

M.C = {
    -- 背景（深空黑蓝 -> 深蓝）
    bg1      = 0x04060D,
    bg2      = 0x0A1024,
    bg3      = 0x070B18,

    -- 面板
    panel    = 0x0C1428,
    panel2   = 0x091020,
    panel3   = 0x121D36,
    line     = 0x1A2745,
    line2    = 0x2A3E68,

    -- 文字
    ink      = 0xE6F0FF,
    ink2     = 0x9CB0CE,
    ink3     = 0x5B7091,

    -- 数据 / 主题色
    cyan     = 0x45DEF7,
    blue     = 0x4E7BFF,
    violet   = 0xA07BFF,
    magenta  = 0xFF6BD6,
    amber    = 0xFFB347,
    gold     = 0xFFD98A,
    green    = 0x4FE3A0,
    red      = 0xFF5A6E,
    white    = 0xFFFFFF,

    ok       = 0x4FE3A0,
    warn     = 0xFFB347,
    danger   = 0xFF5A6E,
}

local C = M.C

-- 夜视红光模式：全局开关，绘制时把颜色压成红色亮度
M.night = false

local function chan(c, shift)
    return math.floor(c / shift) % 256
end

function M.lerp_color(c1, c2, t)
    local r1, g1, b1 = chan(c1, 65536), chan(c1, 256), chan(c1, 1)
    local r2, g2, b2 = chan(c2, 65536), chan(c2, 256), chan(c2, 1)
    local r = math.floor(r1 + (r2 - r1) * t + 0.5)
    local g = math.floor(g1 + (g2 - g1) * t + 0.5)
    local b = math.floor(b1 + (b2 - b1) * t + 0.5)
    return r * 65536 + g * 256 + b
end

--[[夜视颜色映射：保留亮度，色相压到暗红
天文台夜间用红光是为了保护暗适应，这里把任意颜色换成红色亮度
]]
function M.tint(color, k)
    if not M.night then return color end
    local r = chan(color, 65536)
    local g = chan(color, 256)
    local b = chan(color, 1)
    local lum = math.floor(0.30 * r + 0.59 * g + 0.11 * b + 0.5)
    if k then lum = math.floor(lum * k + 0.5) end
    if lum < 0 then lum = 0 end
    if lum > 255 then lum = 255 end
    return lum * 65536 + math.floor(lum * 0.28) * 256 + math.floor(lum * 0.18)
end

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
                color = M.tint(M.lerp_color(c1, c2, t)),
                radius = 0, border_width = 0,
            })
        end
    end
end

function M.label(parent, x, y, w, h, text, size, color, align)
    local lb = airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font = "hzfont",
        font_size = size or 16,
        color = M.tint(color or C.ink),
    })
    if align and align ~= airui.TEXT_ALIGN_LEFT and lb.set_align then
        pcall(lb.set_align, lb, align)
    end
    return lb
end

function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = M.tint(color or C.panel),
        color_opacity = opacity or 255,
        radius = radius or 0, border_width = 0,
    })
end

--[[带描边的盒子（可指定描边宽度/透明度）
]]
function M.frame(parent, x, y, w, h, color, radius, border, bw, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = M.tint(color or C.panel), color_opacity = opacity or 255,
        radius = radius or 12,
        border_color = M.tint(border or C.line), border_width = bw or 1,
    })
end

function M.card(parent, x, y, w, h, color, radius, line_color, line_width)
    return M.frame(parent, x, y, w, h, color or C.panel, radius or 12,
        line_color or C.line, line_width or 1)
end

--[[卡片顶部装饰色条（3px 圆头）
]]
function M.accent_bar(parent, x, y, w, color)
    return M.box(parent, x, y, w, 3, color or C.cyan, 2)
end

-- 1px 水平分隔线
function M.hline(parent, x, y, w, color, opacity)
    return M.box(parent, x, y, w, 1, color or C.line, 0, opacity or 255)
end

function M.button(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font = "hzfont", font_size = size or 20,
        style = {
            bg_color = M.tint(bg or C.cyan), bg_opa = 255,
            text_color = M.tint(fg or 0x061019),
            radius = radius or 12,
            border_width = 0,
            border_color = M.tint(bg or C.cyan),
            pressed_bg_color = M.tint(C.line2),
            pressed_text_color = M.tint(0xFFFFFF),
        },
        on_click = on_click,
    })
end

function M.ghost_button(parent, x, y, w, h, text, size, fg, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font = "hzfont", font_size = size or 16,
        style = {
            bg_color = M.tint(C.panel3), bg_opa = 255,
            text_color = M.tint(fg or C.ink2),
            radius = 10,
            border_width = 1,
            border_color = M.tint(C.line2),
            pressed_bg_color = M.tint(C.line2),
            pressed_text_color = M.tint(0xFFFFFF),
        },
        on_click = on_click,
    })
end

--[[胶囊标签：返回 box 与内部 label 两个对象
]]
function M.pill(parent, x, y, w, h, text, color, size)
    local color_ = color or C.cyan
    local box = M.box(parent, x, y, w, h, color_, h / 2, 46)
    local lb = M.label(box, 0, math.floor((h - (size or 13)) / 2) - 2, w, (size or 13) + 6,
        text or "", size or 13, color_, airui.TEXT_ALIGN_CENTER)
    return box, lb
end

function M.slider(parent, x, y, w, h, minv, maxv, val, ind_color, on_change)
    local ok, sl = pcall(function()
        return airui.slider({
            parent = parent, x = x, y = y, w = w, h = h,
            min = minv, max = maxv, value = val,
            style = {
                bg_color = M.tint(C.line), bg_opa = 255,
                indicator_color = M.tint(ind_color or C.cyan), indicator_opa = 255,
                knob_color = M.tint(0xFFFFFF), knob_opa = 255,
                knob_border_color = M.tint(ind_color or C.cyan), knob_border_width = 2,
                radius = math.floor(h / 2),
            },
            on_change = on_change,
        })
    end)
    return ok and sl or nil
end

function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then
            log.error("ui", "defer error", tostring(err))
        end
    end, ms or 20)
end

function M.shape(config)
    local items = config and config.items
    if items then
        for _, it in ipairs(items) do
            if it.fill then
                if it.color == nil then it.color = it.fill_color or 0xFFFFFF end
                if it.opacity == nil then it.opacity = it.fill_opacity or 255 end
            end
        end
    end
    return airui.shape(config)
end

-- ==================== 状态色 ====================
function M.state_color(s)
    if s == "danger" then return C.danger end
    if s == "warn" then return C.warn end
    return C.ok
end

function M.state_text(s)
    if s == "danger" then return "极差" end
    if s == "warn" then return "一般" end
    return "优秀"
end

-- 观测质量评分（0..1）-> 颜色
function M.quality_color(q)
    if q >= 0.75 then return C.green end
    if q >= 0.45 then return C.amber end
    return C.red
end

-- 按星等取星点颜色（蓝白 -> 暖白 -> 橙）
function M.star_color(mag, bv)
    bv = bv or 0.5
    if bv < 0.0 then return 0xBFD8FF end
    if bv < 0.3 then return 0xDCE9FF end
    if bv < 0.6 then return 0xFFFFFF end
    if bv < 1.0 then return 0xFFF3D6 end
    return 0xFFD2A0
end

return M
