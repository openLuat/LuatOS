--[[
@module  theme
@summary 配色、渐变与基础控件封装（暖色家庭风）
@version 1.0
@date    2026.10.22

所有 UI 模块只从这里取颜色和基础控件，保证风格统一；改配色只改 C 表。
]]
local M = {}

-- ==================== 配色 ====================
M.C = {
    -- 暖色背景（奶油 -> 桃子）
    bg1      = 0xFFF6EA,
    bg2      = 0xFFDDBF,
    bg3      = 0xFFCFA8,

    -- 文字
    ink      = 0x5B3D2A,   -- 主文字：深咖
    ink2     = 0x8B6A52,   -- 次文字
    ink3     = 0xB3927A,   -- 弱文字

    -- 主题色（陶土橘 / 蜜桃 / 奶油白）
    accent   = 0xE4763F,
    accent_d = 0xC85E2C,
    peach    = 0xF2A25C,
    cream    = 0xFFFDF8,
    card     = 0xFFFBF4,
    line     = 0xF0DCC6,
    line2    = 0xE8CDB2,
    green    = 0x7FA86B,
    red      = 0xE06A5C,

    -- 插图
    house    = 0xFFF3E2,
    roof     = 0xD9805A,
    door     = 0xB87A52,
    window   = 0xFFE1A6,
    ground1  = 0xF6CBA6,
    ground2  = 0xEFBC93,
    tree     = 0x8FB07A,
    tree2    = 0x7BA067,
    trunk    = 0xB98A63,
    skin     = 0xF6CFA9,
    hair     = 0x4A3728,
    dad      = 0x7FA6C9,
    mom      = 0xE08FA4,
    kid      = 0xF2C14E,
    pet      = 0xC98B5E,
    pet2     = 0xA9714A,
    sun      = 0xFFD07A,

    -- 深色遮罩（照片查看器控制条）
    mask     = 0x1A120C,
    on_dark  = 0xFFF3E2,
    on_dark2 = 0xD9B79C,
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

--[[竖直渐变：用若干条纯色容器拼出来（容器本身不支持渐变）]]
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
--[[标签]]
function M.label(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text or "",
        font_size = size or 16,
        color = color or C.ink,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

--[[纯色圆角块]]
function M.box(parent, x, y, w, h, color, radius, opacity)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color, color_opacity = opacity or 255,
        radius = radius or 0, border_width = 0,
    })
end

--[[带描边的卡片]]
function M.card(parent, x, y, w, h, color, radius, line_color, line_width)
    return airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 12,
        border_color = line_color or C.line, border_width = line_width or 1,
    })
end

--[[按钮]]
function M.button(parent, x, y, w, h, text, size, bg, fg, on_click, radius)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 20,
        style = {
            bg_color = bg or C.accent, bg_opa = 255,
            text_color = fg or 0xFFFFFF,
            radius = radius or 14,
            border_width = 0,
            border_color = bg or C.accent,
            pressed_bg_color = C.accent_d,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

--[[深色控制条上的小按钮]]
function M.dark_button(parent, x, y, w, h, text, size, on_click, active)
    return airui.button({
        parent = parent, x = x, y = y, w = w, h = h,
        text = text, font_size = size or 18,
        style = {
            bg_color = active and C.accent or 0x3A2A20,
            bg_opa = 255,
            text_color = active and 0xFFFFFF or C.on_dark,
            radius = 12,
            border_width = 1,
            border_color = active and C.accent or 0x5A4436,
            pressed_bg_color = C.accent_d,
            pressed_text_color = 0xFFFFFF,
        },
        on_click = on_click,
    })
end

--[[延迟执行
LVGL 的事件回调里直接 destroy 触发事件的那个控件（或它所在的整页）是危险操作，
统一用 20ms 定时器把“切页/销毁”挪出回调，事件先安全返回。
]]
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then
            log.error("ui", "defer error", tostring(err))
        end
    end, ms or 20)
end

--[[形状封装
LVGL 的 shape 图元只要 fill=true 就会顺便画一圈描边（宽度默认 1，颜色默认白），
所以纯填充图元必须把 color 设成 fill_color，否则每个色块边上都会有一圈白线。
这里统一补一次，业务代码只写 fill_color 就够了。
]]
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

--[[把字节数转成好读的字符串]]
function M.size_text(n)
    n = tonumber(n) or 0
    if n >= 1024 * 1024 then
        return string.format("%.1f MB", n / (1024 * 1024))
    elseif n >= 1024 then
        return string.format("%d KB", math.floor(n / 1024 + 0.5))
    end
    return tostring(n) .. " B"
end

return M
