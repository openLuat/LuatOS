--[[
@module  theme
@summary 工业深色主题：调色板 + 控件工厂（label/卡片/按钮/胶囊/图表/表格/进度条）
@version 1.0
@date    2026.11.10
]]
local M = {}

-- ==================== 调色板 ====================
M.C = {
    bg      = 0x0B1017,   -- 页面底色
    panel   = 0x141C26,   -- 卡片
    panel2  = 0x1C2733,   -- 卡片内嵌块 / 按钮底
    panel3  = 0x243141,   -- 选中态
    line    = 0x27333F,   -- 分隔线 / 边框
    line2   = 0x39485A,   -- 较亮边框
    ink     = 0xE8EEF4,   -- 主文字
    ink2    = 0xA9B7C6,   -- 次文字
    ink3    = 0x6E7F90,   -- 弱文字
    white   = 0xFFFFFF,
    cyan    = 0x00C2FF,
    green   = 0x2ED47A,
    amber   = 0xFFB020,
    red     = 0xFF4D5E,
    orange  = 0xFF9A3C,
    purple  = 0x9B7BFF,
    blue    = 0x35A8E0,
}

-- 文本对齐（= LV_TEXT_ALIGN_*）
M.TEXT_LEFT   = 0
M.TEXT_CENTER = 1
M.TEXT_RIGHT  = 2

local C = M.C

-- ==================== 颜色工具 ====================
-- 两色线性插值，t = 0 取 a，t = 1 取 b
function M.lerp(a, b, t)
    local ar, ag, ab = (a >> 16) & 0xFF, (a >> 8) & 0xFF, a & 0xFF
    local br, bg, bb = (b >> 16) & 0xFF, (b >> 8) & 0xFF, b & 0xFF
    local r = math.floor(ar + (br - ar) * t)
    local g = math.floor(ag + (bg - ag) * t)
    local bl = math.floor(ab + (bb - ab) * t)
    return (r << 16) | (g << 8) | bl
end

-- 把颜色按比例压暗（k = 0.25 表示保留 25% 亮度）
function M.dim(color, k)
    return M.lerp(C.bg, color, k)
end

-- ==================== 基础控件 ====================
function M.label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "", font = "hzfont", font_size = size or 16,
        color = color or C.ink, align = align or M.TEXT_LEFT,
    })
end

function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.panel, radius = radius or 0,
        color_opacity = opacity or 255,
    })
end

function M.hline(parent, x, y, w, color)
    return M.box(parent, x, y, w, 1, color or C.line, 0)
end

function M.vline(parent, x, y, h, color)
    return M.box(parent, x, y, 1, h, color or C.line, 0)
end

-- 圆点（状态灯 / 图例点）
function M.dot(parent, x, y, size, color)
    return M.box(parent, x, y, size, size, color, math.floor(size / 2))
end

-- 卡片：底色 + 细边框，可选标题与右上角副标题
function M.card(parent, x, y, w, h, title, sub)
    local box = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = C.panel, radius = 14, border_color = C.line, border_width = 1,
    })
    if title then
        M.label(box, 18, 14, w - 36, 22, title, 15, C.ink)
        if sub then
            M.label(box, 120, 16, w - 138, 20, sub, 12, C.ink3, M.TEXT_RIGHT)
        end
    end
    return box
end

-- 内嵌面板（卡片里的分区）
function M.frame(parent, x, y, w, h, color, radius, border)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.panel2, radius = radius or 10,
        border_color = border or C.line, border_width = border and 1 or 0,
    })
end

function M.button(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h, text = text,
        font = "hzfont", font_size = size or 16,
        style = {
            bg_color = bg or C.panel2, bg_opa = 255,
            text_color = fg or C.ink, radius = radius or 10,
            border_color = bg or C.panel2, border_width = 0,
            pressed_bg_color = C.line2, pressed_text_color = C.white,
        },
        on_click = on_click,
    })
end

-- 线框按钮（次要操作）
function M.ghost(parent, x, y, w, h, text, size, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h, text = text,
        font = "hzfont", font_size = size or 15,
        style = {
            bg_color = C.panel2, bg_opa = 255,
            text_color = fg or C.ink2, radius = radius or 10,
            border_color = C.line2, border_width = 1,
            pressed_bg_color = C.line2, pressed_text_color = C.white,
        },
        on_click = on_click,
    })
end

-- 胶囊标签，返回 底板, 文字 label
function M.pill(parent, x, y, w, h, text, color, size)
    local box = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = M.dim(color, 0.26), radius = math.floor(h / 2),
        border_color = M.dim(color, 0.55), border_width = 1,
    })
    local lb = M.label(box, 0, math.floor((h - (size or 13) - 4) / 2), w,
        (size or 13) + 6, text or "", size or 13, color, M.TEXT_CENTER)
    return box, lb
end

-- 状态徽标（实心，用于机台状态）
function M.badge(parent, x, y, w, h, text, color, size)
    local box = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, radius = math.floor(h / 3),
    })
    return M.label(box, 0, math.floor((h - (size or 12) - 4) / 2), w,
        (size or 12) + 6, text or "", size or 12, C.bg, M.TEXT_CENTER), box
end

-- ==================== 数据控件 ====================
function M.bar(parent, x, y, w, h, cfg)
    local c = {
        parent = parent, x = x, y = y, w = w, h = h,
        min = 0, max = 100, value = 0, radius = math.floor(h / 2),
        bg_color = C.line, indicator_color = C.green,
    }
    for k, v in pairs(cfg or {}) do c[k] = v end
    return airui.bar(c)
end

function M.slider(parent, x, y, w, h, cfg)
    local c = {
        parent = parent, x = x, y = y, w = w, h = h,
        min = 0, max = 100, value = 0,
        style = {
            bg_color = C.line, indicator_color = C.cyan,
            knob_color = C.ink, radius = 4,
        },
    }
    for k, v in pairs(cfg or {}) do c[k] = v end
    return airui.slider(c)
end

function M.chart(parent, x, y, w, h, cfg)
    local c = {
        parent = parent, x = x, y = y, w = w, h = h,
        bg_color = C.panel, bg_opa = 255,
        border_width = 0, grid_color = C.line, grid_opa = 90,
        y_axis = { min = 0, max = 100 },
    }
    for k, v in pairs(cfg or {}) do c[k] = v end
    return airui.chart(c)
end

function M.table(parent, x, y, w, h, cfg)
    local c = {
        parent = parent, x = x, y = y, w = w, h = h,
        rows = 4, cols = 3,
        border_color = C.line,
        style = {
            bg_color = C.panel2, bg_opa = 255, border_width = 0, radius = 8,
            cell_bg_color = C.panel2, cell_border_color = C.line,
            cell_border_width = 1, cell_text_color = C.ink2,
            cell_text_align = M.TEXT_LEFT, cell_vertical_align = "center",
            cell_font_size = 12,
        },
    }
    for k, v in pairs(cfg or {}) do c[k] = v end
    return airui.table(c)
end

-- KPI 卡：标题 + 大数字 + 单位，返回 数值 label（便于刷新）
function M.kpi(parent, x, y, w, h, title, value, unit, color)
    local box = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = C.panel, radius = 14, border_color = C.line, border_width = 1,
    })
    M.label(box, 16, 12, w - 32, 18, title, 12, C.ink3)
    local vl = M.label(box, 16, 36, w - 60, 40, value, 30, color or C.ink)
    if unit then
        M.label(box, w - 52, 50, 40, 18, unit, 12, C.ink3, M.TEXT_RIGHT)
    end
    return vl, box
end

function M.log_ok(tag, msg)
    log.info(tag or "theme", msg or "")
end

return M
