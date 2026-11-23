--[[
@module ui_kit
@summary SIP_APP 橙白主题与 AirUI 控件工厂
]]

local kit = {}

kit.W = _G.screen_w or 1024
kit.H = _G.screen_h or 600

-- ==================== 颜色 ====================
local C = {
    brand       = 0xFF6500,
    brand2      = 0xFF9D22,
    brand_deep  = 0xE05600,
    brand_soft  = 0xFFF2E3,
    brand_line  = 0xFFD8B0,

    bg          = 0xFFFAF5,
    bg_warm     = 0xFFF3E6,
    card        = 0xFFFFFF,
    card_soft   = 0xFFF7EF,

    text        = 0x252525,
    text2       = 0x7A5B3A,
    text3       = 0xB08A62,
    white       = 0xFFFFFF,
    white_dark  = 0xB9CDDE,

    line        = 0xFFE0BA,
    line_soft   = 0xFFEFDD,

    green       = 0x16B961,
    green_deep  = 0x0E9A4E,
    red         = 0xF04444,
    red_deep    = 0xD32F2F,
    blue        = 0x1E6FD9,

    dark1       = 0x06162F,
    dark2       = 0x0B3A73,
    dark3       = 0x030A18,
}
kit.C = C

-- ==================== 字号 ====================
local FS = {
    tiny = 14, small = 16, body = 18, h3 = 20, h2 = 24, h1 = 30, num = 34,
}
kit.FS = FS

-- ==================== 尺寸 ====================
kit.TOP_H = 64          -- 顶栏
kit.NAV_H = 0          -- 底部导航
kit.PAD   = 12          -- 内容区边距
kit.CONTENT_H = kit.H - kit.TOP_H

-- ==================== 颜色工具 ====================
local function ch(c, shift)
    return math.floor(c / (2 ^ shift)) % 256
end

function kit.mix(c1, c2, t)
    t = math.max(0, math.min(1, t or 0))
    local r = math.floor(ch(c1, 16) * (1 - t) + ch(c2, 16) * t + 0.5)
    local g = math.floor(ch(c1, 8) * (1 - t) + ch(c2, 8) * t + 0.5)
    local b = math.floor(ch(c1, 0) * (1 - t) + ch(c2, 0) * t + 0.5)
    return r * 65536 + g * 256 + b
end

-- 用若干条色带模拟渐变（airui 不暴露 bg_grad_* 样式）
function kit.grad(parent, x, y, w, h, c1, c2, steps)
    steps = steps or 8
    local layer = parent
    local band_h = math.ceil(h / steps)
    for i = 0, steps - 1 do
        local by = y + i * band_h
        local bh = math.min(band_h, y + h - by)
        if bh > 0 then
            kit.box(layer, {
                x = x, y = by, w = w, h = bh,
                color = kit.mix(c1, c2, (steps <= 1) and 0 or (i / (steps - 1))),
            })
        end
    end
end

-- ==================== 基础控件 ====================
function kit.box(parent, o)
    o = o or {}
    if not airui then return nil end
    local obj = airui.container({
        parent = parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 100, h = o.h or 100,
        color = o.color, color_opacity = o.opacity,
        radius = o.radius or 0,
        border_color = o.border and (o.border_color or C.line) or nil,
        border_width = o.border and (o.border_width or 1) or nil,
        on_click = o.on_click,
        on_long_press = o.on_long_press,
        scroll = o.scroll or false,
    })
    assert(obj, "AirUI container creation failed")
    if obj and o.clip ~= false and obj.set_clip then pcall(obj.set_clip, obj, true) end
    return obj
end

function kit.label(parent, o)
    o = o or {}
    if not airui then return nil end
    local obj = airui.label({
        parent = parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 100, h = o.h or ((o.size or FS.body) + 6),
        text = o.text or "",
        font_size = o.size or FS.body,
        color = o.color or C.text,
        align = o.align or airui.TEXT_ALIGN_LEFT,
        on_click = o.on_click,
    })
    assert(obj, "AirUI label creation failed")
    return obj
end

function kit.card(parent, o)
    o = o or {}
    o.color = o.color or C.card
    o.radius = o.radius or 18
    if o.border == nil then o.border = true end
    o.border_color = o.border_color or C.line_soft
    return kit.box(parent, o)
end

-- 按钮：kind = primary / ghost / soft / green / red / plain / nav
function kit.btn(parent, o)
    o = o or {}
    if not airui then return nil end
    local kind = o.kind or "primary"
    local bg, fg, border_color, border_width, pressed
    if kind == "primary" then
        bg, fg, pressed = C.brand, C.white, C.brand_deep
    elseif kind == "green" then
        bg, fg, pressed = C.green, C.white, C.green_deep
    elseif kind == "red" then
        bg, fg, pressed = C.red, C.white, C.red_deep
    elseif kind == "ghost" then
        bg, fg, border_color, border_width, pressed = C.white, C.brand, C.brand_line, 1, C.brand_soft
    elseif kind == "soft" then
        bg, fg, pressed = C.brand_soft, C.brand, C.brand_line
    elseif kind == "plain" then
        bg, fg, pressed = C.card_soft, C.text2, C.brand_soft
    else
        bg, fg, pressed = C.bg_warm, C.text, C.brand_soft
    end
    local obj = airui.button({
        parent = parent,
        x = o.x or 0, y = o.y or 0,
        w = o.w or 120, h = o.h or 48,
        text = o.text or "",
        font_size = o.size or FS.body,
        style = {
            bg_color = bg, bg_opa = 255,
            text_color = fg,
            border_color = border_color or bg,
            border_width = border_width or 0,
            radius = o.radius or 14,
            pad = o.pad or 2,
            pressed_bg_color = pressed,
            pressed_text_color = (kind == "ghost") and C.brand or fg,
        },
        on_click = o.on_click and function(...)
            -- Coordinates only: never log input keys, account text or passwords.
            log.info("sip_ui", "button click", o.x or 0, o.y or 0)
            return o.on_click(...)
        end or nil,
    })
    assert(obj, "AirUI button creation failed")
    return obj
end

-- 圆形头像：取名字/号码前两个字
function kit.avatar(parent, o)
    o = o or {}
    local d = o.size or 56
    local text = o.text or "?"
    local box = kit.box(parent, {
        x = o.x or 0, y = o.y or 0, w = d, h = d,
        color = o.color or C.brand, radius = math.floor(d / 2),
    })
    if not box then return nil end
    kit.label(box, {
        x = 0, y = math.floor((d - (o.font_size or FS.h3)) / 2) - 2,
        w = d, h = (o.font_size or FS.h3) + 4,
        text = text, size = o.font_size or FS.h3,
        color = C.white, align = airui.TEXT_ALIGN_CENTER,
    })
    return box
end

function kit.line(parent, o)
    o = o or {}
    return kit.box(parent, {
        x = o.x or 0, y = o.y or 0, w = o.w or 100, h = o.h or 1,
        color = o.color or C.line_soft,
    })
end

--[[带描边的输入框（airui 的 textarea 不支持描边，用外层容器画边）
  o: x,y,w,h,text,placeholder,max_len,password,size,on_change
  return: textarea 对象（用于 get_text / attach_keyboard）]]
function kit.input(parent, o)
    o = o or {}
    local wrap = kit.box(parent, {
        x = o.x or 0, y = o.y or 0, w = o.w or 200, h = o.h or 46,
        color = C.white, radius = o.radius or 12,
        border = true, border_color = o.border_color or C.brand_line,
    })
    if not wrap then return nil end
    local ta = airui.textarea({
        parent = wrap,
        x = 8, y = math.max(2, math.floor(((o.h or 46) - (o.size or FS.body) - 8) / 2)),
        w = (o.w or 200) - 16, h = (o.size or FS.body) + 10,
        text = o.text or "",
        placeholder = o.placeholder or "",
        max_len = o.max_len or 64,
        mode = o.password and "password" or "normal",
        font_size = o.size or FS.body,
        align = o.align or airui.TEXT_ALIGN_LEFT,
        on_text_change = o.on_change,
        style = { bg_color = C.white, text_color = C.text, radius = 0 },
    })
    assert(ta, "AirUI textarea creation failed")
    return ta
end

-- 大号数字键盘按键
function kit.key(parent, o)
    return kit.btn(parent, {
        x = o.x, y = o.y, w = o.w or 120, h = o.h or 62,
        text = o.text, size = o.size or FS.h2,
        kind = o.kind or "nav", radius = 16,
        on_click = o.on_click,
    })
end

-- ==================== 工具 ====================
function kit.destroy(obj)
    if obj then pcall(obj.destroy, obj) end
end

-- 估算文本宽度（用于 toast/气泡宽度）
function kit.text_w(str, size)
    if not str then return 0 end
    size = size or FS.small
    local w = 0
    for _, code in utf8.codes(str) do
        if code > 0x2E80 then w = w + size else w = w + math.floor(size * 0.56) end
    end
    return w
end

-- 按字符截断（中英文混排安全）
function kit.ellipsis(str, n)
    if not str or str == "" then return "" end
    local len = utf8.len(str)
    if not len or len <= n then return str end
    local off = utf8.offset(str, n + 1)
    if not off then return str end
    return str:sub(1, off - 1) .. "…"
end

-- 取显示用首字（头像）
function kit.first_char(str)
    if not str or str == "" then return "?" end
    local ok, _, code = pcall(utf8.codes(str), str, 0)
    if ok and code then
        local s = utf8.char(code)
        if s and s ~= "" then return s end
    end
    return str:sub(1, 1)
end

return kit
