--[[
@module  theme
@summary 失物招领公示 - 暖色明亮主题 + 基础控件封装
@version 1.0
@date    2026.10.30
@usage
所有 UI 模块只从这里取颜色和基础控件，改配色只改 C 表。
状态色约定：拾得=琥珀橙、遗失=蓝、公示中=绿、已认领=灰。
亮色主题下大面积留白不填充，脏矩形小、软件渲染更跟手。
]]

local M = {}

M.C = {
    -- 背景（暖纸色，明亮柔和）
    bg1   = 0xF7F3EC,
    bg2   = 0xEFE8DC,

    -- 文字
    ink   = 0x2A2724,
    ink2  = 0x6B6358,
    ink3  = 0xA79E90,

    -- 容器
    panel = 0xFFFFFF,
    card  = 0xFFFFFF,
    card2 = 0xFBF8F1,
    line  = 0xE8E0D2,
    line2 = 0xD8CEBC,

    -- 状态色
    found       = 0xE07B26,   -- 拾得（琥珀橙）
    found_dark  = 0xB85F14,
    found_soft  = 0xFCEEDC,
    lost        = 0x3E7CB1,   -- 遗失（蓝）
    lost_dark   = 0x2C5F8A,
    lost_soft   = 0xE4EEF7,
    open        = 0x2FA96B,   -- 公示中（绿）
    open_soft   = 0xE3F4EA,
    done        = 0x9AA5B1,   -- 已认领（灰）
    done_soft   = 0xEFF2F5,
    danger      = 0xD64A3A,   -- 删除 / 告警

    -- 强调
    accent = 0xE07B26,
    gold   = 0xC79A3B,
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
        color = color or C.card, radius = radius or 12,
        border_color = line_color or C.line, border_width = line_width or 1,
    })
end

-- 按钮样式：primary 强调 / ghost 描边 / danger 危险 / success 成功
local BTN = {
    primary = { bg = C.accent, fg = 0xFFFFFF, border = C.accent, press = C.found_dark },
    ghost   = { bg = C.panel,  fg = C.ink2,   border = C.line2,   press = C.card2 },
    danger  = { bg = C.panel,  fg = C.danger, border = C.danger,  press = 0xFBE9E5 },
    success = { bg = C.open,   fg = 0xFFFFFF, border = C.open,    press = 0x258C58 },
    lost    = { bg = C.lost,   fg = 0xFFFFFF, border = C.lost,    press = C.lost_dark },
}

function M.button(parent, x, y, w, h, text, size, on_click, kind)
    local s = BTN[kind] or BTN.primary
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = s.bg, bg_opa = 255,
            text_color = s.fg,
            radius = 10,
            border_width = 1,
            border_color = s.border,
            pressed_bg_color = s.press,
            pressed_text_color = s.fg,
        },
        on_click = on_click,
    })
end

--[[胶囊形筛选 chip：container + 居中文字，可切换选中态
返回 { box, lb, set_active }]]
function M.chip(parent, x, y, w, h, text, size, on_click)
    local box = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = C.panel, radius = math.floor(h / 2),
        border_color = C.line2, border_width = 1,
        on_click = on_click,
    })
    local ty = math.max(0, math.floor((h - size * 1.4) / 2))
    local lb = M.label(box, 0, ty, w, size * 1.4, text, size, C.ink2, airui.TEXT_ALIGN_CENTER)
    local api = { box = box, lb = lb }
    function api.set_active(on)
        box:set_color(on and C.accent or C.panel, 255)
        lb:set_color(on and 0xFFFFFF or C.ink2)
    end
    return api
end

--[[延迟执行：LVGL 事件回调里直接销毁控件是危险操作，挪到定时器里做]]
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer error", tostring(err)) end
    end, ms or 20)
end

return M
