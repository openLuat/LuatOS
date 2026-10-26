--[[
@module  theme
@summary 工业深色主题：配色 + 基础控件封装
@author  王世豪
@version 1.0
@date    2026.10.26
@usage
所有 UI 模块只从这里取颜色和基础控件，改配色只改 C 表。
状态色固定：运行=绿、待机=灰蓝、异常=红、换型=蓝。
]]
local M = {}

M.C = {
    -- 背景（近黑，车间强光下对比度高）
    bg1   = 0x05080C,
    bg2   = 0x0B1218,
    bg3   = 0x121C26,

    -- 文字
    ink   = 0xE6EDF3,
    ink2  = 0x8FA3B8,
    ink3  = 0x5A6B7D,

    -- 容器
    panel = 0x101A24,
    card  = 0x16222E,
    card2 = 0x1B2A38,
    line  = 0x24323F,
    line2 = 0x2E4050,

    -- 状态色
    run        = 0x2ECC71,
    run_dark   = 0x1B7A45,
    idle       = 0x607D8B,
    idle_dark  = 0x33424C,
    alarm      = 0xE74C3C,
    alarm_dark = 0x7E2419,
    warn       = 0xF1C40F,
    changeover = 0x3498DB,
    offline    = 0x394654,

    -- 强调
    accent = 0x00BCD4,
    gold   = 0xFFC46B,
}

local C = M.C

-- ==================== 颜色工具 ====================
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
        color = color or C.card, radius = radius or 10,
        border_color = line_color or C.line, border_width = line_width or 1,
    })
end

function M.button(parent, x, y, w, h, text, size, on_click, active)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = active and C.accent or C.panel, bg_opa = 255,
            text_color = active and 0xFFFFFF or C.ink,
            radius = 10,
            border_width = 1,
            border_color = active and C.accent or C.line,
            pressed_bg_color = C.accent,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

--[[延迟执行：LVGL 事件回调里直接销毁控件是危险操作，挪到定时器里做]]
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer error", tostring(err)) end
    end, ms or 20)
end

return M
