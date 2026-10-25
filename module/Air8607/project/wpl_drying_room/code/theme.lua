--[[
@module  theme
@summary 暖色科技风配色与基础控件封装（深棕 + 琥珀，贴合烘干场景）
@version 1.0
@date    2026.10.24
]]
local M = {}

M.C = {
    -- 背景（深棕黑 -> 深棕）
    bg1      = 0x1A120C,
    bg2      = 0x2E1E13,

    -- 面板
    panel    = 0x261A11,
    panel2   = 0x1C130C,
    line     = 0x3D2A1B,
    line2    = 0x5A3F28,

    -- 文字
    ink      = 0xF7EFE4,
    ink2     = 0xC9B49E,
    ink3     = 0x8A7159,

    -- 数据色
    amber    = 0xFFA62B,   -- 主色：琥珀
    orange   = 0xFF7A3D,
    gold     = 0xFFD166,
    red      = 0xFF4D4E,
    green    = 0x7ED957,
    blue     = 0x5AA9E6,
    violet   = 0xA98BF0,

    ok       = 0x7ED957,
    warn     = 0xFFB020,
    danger   = 0xFF4D4E,
}

local C = M.C

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
        color = color or C.amber, radius = 2, border_width = 0,
    })
end

function M.button(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = bg or C.amber, bg_opa = 255,
            text_color = fg or 0x1A120C,
            radius = radius or 12,
            border_width = 0,
            border_color = bg or C.amber,
            pressed_bg_color = C.line2,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

function M.ghost_button(parent, x, y, w, h, text, size, fg, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 16,
        style = {
            bg_color = C.panel2, bg_opa = 255,
            text_color = fg or C.ink2,
            radius = 10,
            border_width = 1,
            border_color = C.line2,
            pressed_bg_color = C.line2,
            pressed_text_color = 0xFFFFFF,
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

function M.size_text(n)
    n = tonumber(n) or 0
    if n >= 1024 * 1024 then
        return string.format("%.1f MB", n / (1024 * 1024))
    elseif n >= 1024 then
        return string.format("%d KB", math.floor(n / 1024 + 0.5))
    end
    return tostring(n) .. " B"
end

function M.state_color(s)
    if s == "danger" then return C.danger end
    if s == "warn" then return C.warn end
    return C.ok
end

function M.state_text(s)
    if s == "danger" then return "报警" end
    if s == "warn" then return "偏离" end
    return "正常"
end

return M
