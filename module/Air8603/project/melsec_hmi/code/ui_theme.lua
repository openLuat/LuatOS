--[[
@module  ui_theme
@summary 工业暗色主题 + 基础控件封装（深蓝黑底 + 青/琥珀/红）
@version 1.0.0
@date    2026.11.09
]]
local conf = require "conf"

local M = {}

M.C = {
    -- 背景
    bg1    = 0x080E18,
    bg2    = 0x111A28,
    -- 面板
    panel  = 0x152031,
    panel2 = 0x0E1725,
    line   = 0x22334A,
    line2  = 0x33506E,
    -- 文字
    ink    = 0xE9F1FB,
    ink2   = 0xA2B6CD,
    ink3   = 0x6B819B,
    -- 数据色
    cyan   = 0x22D3EE,
    blue   = 0x4C8DFF,
    green  = 0x3DDC97,
    amber  = 0xFFB020,
    red    = 0xFF5A5F,
    -- 状态
    ok     = 0x3DDC97,
    warn   = 0xFFB020,
    danger = 0xFF5A5F,
    off    = 0x5A6E86,
}

local C = M.C
local SW = conf.W

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

-- 竖向渐变背景（用若干色带模拟，避免 extra 组件依赖）
function M.gradient(parent, x, y, w, h, c1, c2, steps)
    steps = steps or 10
    local sh = math.ceil(h / steps)
    for i = 0, steps - 1 do
        local t = (steps > 1) and (i / (steps - 1)) or 0
        local yy = y + i * sh
        local hh = sh
        if yy + hh > y + h then
            hh = y + h - yy
        end
        if hh > 0 then
            airui.container({
                parent = parent, x = x, y = yy, w = w, h = hh,
                color = M.lerp_color(c1, c2, t),
                radius = 0, border_width = 0,
            })
        end
    end
end

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
        color = color or C.panel, radius = radius or 12,
        border_color = line_color or C.line, border_width = line_width or 1,
    })
end

function M.accent_bar(parent, x, y, w, color)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = 3,
        color = color or C.cyan, radius = 2, border_width = 0,
    })
end

function M.button(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 18,
        style = {
            bg_color = bg or C.cyan, bg_opa = 255,
            text_color = fg or 0x05141C,
            radius = radius or 10,
            border_width = 0,
            border_color = bg or C.cyan,
            pressed_bg_color = C.line2,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

function M.ghost_button(parent, x, y, w, h, text, size, fg, on_click, border)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 15,
        style = {
            bg_color = C.panel2, bg_opa = 255,
            text_color = fg or C.ink2,
            radius = 9,
            border_width = 1,
            border_color = border or C.line2,
            pressed_bg_color = C.line2,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

-- 在协程中延后执行（避免在 LVGL 事件回调里直接销毁控件）
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then
            log.error("ui", "defer error", tostring(err))
        end
    end, ms or 20)
end

-- 状态小圆点
function M.dot(parent, x, y, r, color)
    return M.box(parent, x, y, r * 2, r * 2, color, r)
end

-- 状态胶囊（底色半透明 + 同色文字）
function M.pill(parent, x, y, w, h, text, color, size)
    local b = M.box(parent, x, y, w, h, color, math.floor(h / 2), 45)
    local t = M.label(b, 0, math.floor((h - 18) / 2), w, 18, text, size or 12, color,
        airui.TEXT_ALIGN_CENTER)
    return b, t
end

-- 底部页面导航
function M.TABS()
    return {
        { id = "dashboard", name = "监控" },
        { id = "trend",     name = "趋势" },
        { id = "alarm",     name = "报警" },
        { id = "settings",  name = "设置" },
    }
end

function M.navbar(parent, cur, y, on_switch)
    local tabs = M.TABS()
    local bw, gap = 200, 10
    local total = #tabs * bw + (#tabs - 1) * gap
    local x0 = math.floor((SW - total) / 2)
    for i, t in ipairs(tabs) do
        local sel = (t.id == cur)
        M.button(parent, x0 + (i - 1) * (bw + gap), y, bw, 40, t.name, 17,
            sel and C.cyan or C.panel2, sel and 0x05141C or C.ink2,
            function()
                M.defer(function()
                    on_switch(t.id)
                end)
            end, 10)
    end
end

-- 安全设置文字（对象可能已被销毁）
function M.set_text(obj, text)
    if obj then
        pcall(obj.set_text, obj, text)
    end
end

function M.set_color(obj, color)
    if obj then
        pcall(obj.set_color, obj, color)
    end
end

return M
