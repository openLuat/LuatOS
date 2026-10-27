--[[
@module  theme
@summary 配色与基础控件封装（深夜蓝基调，clock/calendar）
@author  王世豪
@version 1.0
@date    2026.10.26

所有 UI 模块只从这里取颜色和基础控件，改配色只改 C 表。
]]
local M = {}

-- ==================== 配色（深夜 -> 星蓝）====================
M.C = {
    bg1   = 0x070B16,
    bg2   = 0x101A33,
    bg3   = 0x182A4E,

    -- 文字
    ink   = 0xE8EEFF,
    ink2  = 0x9FB0D8,
    ink3  = 0x6B7CA8,

    -- 主题强调
    accent   = 0x4FC3F7,
    accent_d = 0x2B8FD1,
    gold     = 0xFFC46B,
    today    = 0xFF6B6B,

    -- 容器
    card  = 0x0F1830,
    panel = 0x0C1428,
    line  = 0x22304F,
    line2 = 0x2C3C60,
}

local C = M.C

-- ==================== 颜色工具 ====================
local function chan(c, shift)
    return math.floor(c / shift) % 256
end

--[[线性插值两个 0xRRGGBB 颜色]]
function M.lerp_color(c1, c2, t)
    local r1, g1, b1 = chan(c1, 65536), chan(c1, 256), chan(c1, 1)
    local r2, g2, b2 = chan(c2, 65536), chan(c2, 256), chan(c2, 1)
    local r = math.floor(r1 + (r2 - r1) * t + 0.5)
    local g = math.floor(g1 + (g2 - g1) * t + 0.5)
    local b = math.floor(b1 + (b2 - b1) * t + 0.5)
    return r * 65536 + g * 256 + b
end

--[[竖直渐变：容器不支持渐变，用若干条纯色容器拼出来]]
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

-- ==================== 基础控件 ====================
function M.label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font_size = size or 16,
        color = color or C.ink,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opacity or 255,
        radius = radius or 0, border_width = 0,
    })
end

function M.card(parent, x, y, w, h, color, radius, line_color, line_width)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 12,
        border_color = line_color or C.line, border_width = line_width or 1,
    })
end

--[[按钮：active=true 时高亮（用于开关类）]]
function M.button(parent, x, y, w, h, text, size, on_click, active)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = active and C.accent or C.panel, bg_opa = 255,
            text_color = active and 0xFFFFFF or C.ink,
            radius = 12,
            border_width = 1,
            border_color = active and C.accent or C.line,
            pressed_bg_color = C.accent_d,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

--[[延迟执行：LVGL 事件回调里直接销毁触发事件的控件是危险操作，
统一挪到定时器里执行，先让事件安全返回。]]
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer error", tostring(err)) end
    end, ms or 20)
end

return M
