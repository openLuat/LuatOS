--[[
@module  theme
@summary 配色与基础控件封装（治愈风：奶油白 + 蜜桃橙）
@author  蒋骞
@version 1.0
@date    2026.10.30

所有 UI 模块只从这里取颜色和基础控件，改配色只改 C 表。
]]
local M = {}

-- ==================== 配色（奶油白 -> 浅杏）====================
M.C = {
    bg1   = 0xFFFCF8,   -- 奶油白
    bg2   = 0xFCEFE7,   -- 浅杏
    bg3   = 0xF8E2D6,

    -- 文字（暖褐系，避免纯黑显得生硬）
    ink   = 0x5D4A44,
    ink2  = 0x9C887F,
    ink3  = 0xCBBCB4,

    -- 主题强调
    accent   = 0xF0957C,   -- 蜜桃
    accent_d = 0xDD7C62,
    gold     = 0xEFB45E,
    today    = 0xE8675C,   -- 今天的高亮描边

    -- 节假日（法定 / 传统节日当天用这一组酒红色，和心情色区分开）
    fest      = 0xD9534F,
    fest_bg   = 0xFFF3EF,
    fest_line = 0xF5CEC5,

    -- 容器
    card  = 0xFFFFFF,
    panel = 0xFFF6F0,
    line  = 0xF1DED4,
    line2 = 0xE7CDC0,

    -- 遮罩
    mask  = 0x3A2A26,
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

--[[调浅：t = 0 原色，t = 1 纯白]]
function M.tint(color, t)
    return M.lerp_color(color, 0xFFFFFF, t)
end

--[[调深：t = 0 原色，t = 1 纯黑]]
function M.shade(color, t)
    return M.lerp_color(color, 0x000000, t)
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

--[[纯色块（无边框、无圆角），常用作分隔线 / 图例色块 / 条形底]]
function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opacity or 255,
        radius = radius or 0, border_width = 0,
    })
end

--[[卡片：白底 + 1px 暖色描边 + 圆角]]
function M.card(parent, x, y, w, h, color, radius, line_color, line_width)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 16,
        border_color = line_color or C.line, border_width = line_width or 1,
    })
end

--[[透明容器（只做布局分组，不画任何东西）]]
function M.plain(parent, x, y, w, h)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = 0x000000, color_opacity = 0, radius = 0, border_width = 0,
    })
end

function M.divider(parent, x, y, w, color)
    return M.box(parent, x, y, w, 1, color or C.line, 0, 255)
end

--[[按钮：active=true 时高亮]]
function M.button(parent, x, y, w, h, text, size, on_click, active)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = active and C.accent or C.panel, bg_opa = 255,
            text_color = active and 0xFFFFFF or C.ink,
            radius = 14,
            border_width = 1,
            border_color = active and C.accent or C.line2,
            pressed_bg_color = C.accent_d,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

--[[心情按钮：底色就是该档心情色，文字用调深后的同色，选中时加粗描边]]
function M.mood_button(parent, x, y, w, h, mood, on_click)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = mood.name, font_size = 24,
        style = {
            bg_color = mood.color, bg_opa = 255,
            text_color = M.shade(mood.color, 0.55),
            radius = 18,
            border_width = 2,
            border_color = M.tint(mood.color, 0.35),
            pressed_bg_color = M.shade(mood.color, 0.12),
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

--[[延迟执行：LVGL 事件回调里不要直接做大动作（重绘大量控件 / 切页面），
统一挪到定时器里执行，先让事件安全返回。]]
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer error", tostring(err)) end
    end, ms or 20)
end

return M
