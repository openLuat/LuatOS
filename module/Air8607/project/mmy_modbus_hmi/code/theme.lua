--[[
@module  theme
@summary 工业暗色科技风配色 + 基础控件封装（深蓝黑 + 青/琥珀，贴合 SCADA 场景）
@version 1.0.0
@date    2026.10.25
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
    violet = 0xA78BFA,
    teal   = 0x2DD4BF,
    pink   = 0xF472B6,

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

function M.gradient(parent, x, y, w, h, c1, c2, steps)
    steps = steps or 10
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
        color = color or C.panel, radius = radius or 10,
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

--[[
透明触摸热区：只用来捕获点击坐标，不带视觉表现。
airui 的 on_click 回调不提供坐标，所以在曲线上按列铺一排热区，
由热区序号反推被点击的位置（见 ui_trend 的游标实现）。
]]
function M.hotspot(parent, x, y, w, h, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = "", font_size = 8,
        style = {
            bg_color = C.cyan, bg_opa = 0,
            text_color = C.cyan,
            radius = 0,
            border_width = 0, border_color = C.cyan,
            pressed_bg_color = C.cyan, pressed_bg_opa = 46,
            pressed_text_color = C.cyan,
        },
        on_click = on_click,
    })
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

function M.state_color(s)
    if s == "danger" then return C.danger end
    if s == "warn" then return C.warn end
    if s == "offline" then return C.off end
    return C.ok
end

function M.state_text(s)
    if s == "danger" then return "报警" end
    if s == "warn" then return "偏离" end
    if s == "offline" then return "离线" end
    return "正常"
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

-- 底部页面导航条
function M.TABS()
    return {
        { id = "dashboard", name = "总览" },
        { id = "trend",     name = "趋势" },
        { id = "alarm",     name = "报警" },
        { id = "regtool",   name = "寄存器" },
        { id = "settings",  name = "设置" },
    }
end

function M.navbar(parent, cur, y, on_switch)
    local tabs = M.TABS()
    local bw, gap = 186, 8
    local total = #tabs * bw + (#tabs - 1) * gap
    local x0 = math.floor((SW - total) / 2)
    for i, t in ipairs(tabs) do
        local sel = (t.id == cur)
        M.button(parent, x0 + (i - 1) * (bw + gap), y, bw, 40, t.name, 17,
            sel and C.cyan or C.panel2, sel and 0x05141C or C.ink2,
            function()
                M.defer(function() on_switch(t.id) end)
            end, 10)
    end
end

-- 页面通用顶栏（返回区 + 标题 + 右侧信息）
function M.page_header(parent, title, right_text, right_color)
    M.box(parent, 0, 0, SW, 56, 0x0A1420)
    M.accent_bar(parent, 0, 54, SW, C.line)
    M.label(parent, 24, 12, 520, 32, title, 24, C.ink)
    local r = M.label(parent, 560, 16, 440, 26, right_text or "", 14,
        right_color or C.ink3, airui.TEXT_ALIGN_RIGHT)
    return r
end

return M
