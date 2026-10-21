--[[
@module ui_widget
@summary 毛玻璃视觉组件封装（卡片 / 胶囊开关 / 按钮 / 档位按钮 / 文本）
@version 1.0
@usage 全部基于 LuatOS 核心库 airui 实现，只使用官方文档中确认存在的接口：
       airui.container / airui.label / airui.image
       container:set_color(color[,opacity])、container:set_border_color(color[,width])
       container:set_pos(x,y)、label:set_text(text)、label:set_color(color)
]]

local T = require "ui_theme"
local M = {}

--------------------------------------------------------------------
-- 基础能力
--------------------------------------------------------------------

-- 半透明填充：container:set_color(color[, opacity])
-- 万一某些固件版本的 set_color 不接受第二个参数，退化为纯色，保证不崩。
function M.glass(obj, color, opacity)
    if not obj then return end
    local ok = pcall(function() obj:set_color(color, opacity) end)
    if not ok then
        pcall(function() obj:set_color(color) end)
    end
end

-- 高光描边：container:set_border_color(color[, width])
function M.border(obj, color, width)
    if not obj then return end
    pcall(function() obj:set_border_color(color, width or 2) end)
end

-- 文本（自动按行高做垂直居中）
function M.text(parent, cfg)
    local h = cfg.h or 28
    return airui.label({
        parent    = parent,
        text      = cfg.text or "",
        x         = cfg.x or 0,
        y         = cfg.y or 0,
        w         = cfg.w or 120,
        h         = h,
        font_size = cfg.size or T.f.body,
        color     = cfg.color or T.c.text,
        align     = cfg.align or airui.TEXT_ALIGN_LEFT,
        font_weight = cfg.weight,
    })
end

-- 在一行/一块区域内垂直居中放置文本
function M.text_mid(parent, cfg)
    local size = cfg.size or T.f.body
    local h    = cfg.h or 32
    local y    = cfg.y + math.floor((h - size * 1.4) / 2)
    if y < cfg.y then y = cfg.y end
    return M.text(parent, {
        text = cfg.text, x = cfg.x, y = y, w = cfg.w, h = h,
        size = size, color = cfg.color, align = cfg.align, weight = cfg.weight,
    })
end

--------------------------------------------------------------------
-- 毛玻璃卡片
--------------------------------------------------------------------
-- cfg = { parent, x, y, w, h, color, opacity, radius, border, border_w, shadow_opa }
function M.card(cfg)
    local card = airui.container({
        parent = cfg.parent or airui.screen,
        x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        color  = cfg.color or T.c.card,
        radius = cfg.radius or T.r.card,
        shadow = {
            offset_x = 0,
            offset_y = 8,
            blur     = 20,
            color    = T.c.shadow,
            opacity  = cfg.shadow_opa or 0.30,
        },
        on_click = cfg.on_click,
    })

    -- 半透明磨砂底 + 暖色高光描边 = 毛玻璃质感
    M.glass(card, cfg.color or T.c.card, cfg.opacity or T.o.card)
    M.border(card, cfg.border or T.c.card_edge, cfg.border_w or 2)

    -- 顶部一道更亮的高光，模拟玻璃边缘的反光
    local hl = airui.container({
        parent = card,
        x = 20, y = 1, w = cfg.w - 40, h = 2,
        color = 0xFFFFFF, radius = 1,
    })
    M.glass(hl, 0xFFFFFF, 140)

    return card
end

--------------------------------------------------------------------
-- 胶囊开关（灯光 / 窗帘）
--------------------------------------------------------------------
-- cfg = { parent, x, y, w, h, on, on_color, off_color, on_change }
-- 返回 { set(on[,nofity]), get(), toggle(), track, knob }
function M.switch(parent, cfg)
    local w = cfg.w or 62
    local h = cfg.h or 32
    local knob_d = h - 8

    local handle = {}
    local on = cfg.on and true or false

    local track = airui.container({
        parent = parent, x = cfg.x, y = cfg.y, w = w, h = h,
        color  = T.c.sw_off,
        radius = math.floor(h / 2),
        on_click = function() handle.toggle() end,
    })

    local knob = airui.container({
        parent = track,
        x = on and (w - knob_d - 4) or 4, y = 4, w = knob_d, h = knob_d,
        color  = T.c.knob,
        radius = math.floor(knob_d / 2),
        on_click = function() handle.toggle() end,
    })

    local function render()
        M.glass(track, on and (cfg.on_color or T.c.sw_on) or (cfg.off_color or T.c.sw_off),
            on and 255 or T.o.sw_off)
        pcall(function() knob:set_pos(on and (w - knob_d - 4) or 4, 4) end)
    end

    function handle.set(v, notify)
        local nv = v and true or false
        if nv == on then
            render()
            return
        end
        on = nv
        render()
        if notify ~= false and cfg.on_change then cfg.on_change(on) end
    end

    function handle.get() return on end
    function handle.toggle() handle.set(not on) end

    handle.track = track
    handle.knob  = knob
    handle.set(cfg.on, false)

    return handle
end

--------------------------------------------------------------------
-- 按钮（圆角矩形 / 圆形）
--------------------------------------------------------------------
-- cfg = { parent, x, y, w, h, text, size, color, opacity, text_color, radius, on_click }
function M.button(parent, cfg)
    local h = cfg.h or 44
    local btn = airui.container({
        parent = parent, x = cfg.x, y = cfg.y, w = cfg.w, h = h,
        color  = cfg.color or T.c.btn,
        radius = cfg.radius or math.floor(h / 2),
        on_click = cfg.on_click,
    })
    M.glass(btn, cfg.color or T.c.btn, cfg.opacity or T.o.btn)

    if cfg.text then
        local lbl = M.text_mid(parent, {
            text = cfg.text, x = cfg.x, y = cfg.y, w = cfg.w, h = h,
            size = cfg.size or 20, color = cfg.text_color or T.c.btn_text,
            align = airui.TEXT_ALIGN_CENTER, weight = cfg.weight,
        })
        -- 关键：文字上也绑定点击，否则触屏点到文字区域时按钮不响应
        if cfg.on_click then lbl:set_on_click(cfg.on_click) end
    end
    return btn
end

--------------------------------------------------------------------
-- 档位按钮（空调风速 低/中/高）
--------------------------------------------------------------------
-- 返回 { set_active(bool), box, label }
function M.chip(parent, cfg)
    local h = cfg.h or 32
    local box = airui.container({
        parent = parent, x = cfg.x, y = cfg.y, w = cfg.w, h = h,
        color  = T.c.chip_off,
        radius = math.floor(h / 2),
        on_click = cfg.on_click,
    })
    local lbl = M.text_mid(parent, {
        text = cfg.text, x = cfg.x, y = cfg.y, w = cfg.w, h = h,
        size = cfg.size or T.f.sub, color = T.c.chip_off_t,
        align = airui.TEXT_ALIGN_CENTER,
    })
    -- 关键：文字上也绑定点击，否则触屏点到文字区域时档位不切换
    if cfg.on_click then lbl:set_on_click(cfg.on_click) end

    local handle = {}
    function handle.set_active(active)
        M.glass(box, active and T.c.chip_on or T.c.chip_off,
            active and 255 or T.o.chip)
        pcall(function() lbl:set_color(active and T.c.chip_on_t or T.c.chip_off_t) end)
    end
    handle.set_active(cfg.active)
    handle.box = box
    handle.label = lbl
    return handle
end

--------------------------------------------------------------------
-- 细线条（分隔线 / 装饰条）
--------------------------------------------------------------------
function M.line(parent, x, y, w, h, color, opacity)
    local obj = airui.container({
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or T.c.divider, radius = math.floor(h / 2),
    })
    M.glass(obj, color or T.c.divider, opacity or 160)
    return obj
end

--------------------------------------------------------------------
-- 小圆点（在线状态指示）
--------------------------------------------------------------------
function M.dot(parent, x, y, d, color, opacity)
    local obj = airui.container({
        parent = parent, x = x, y = y, w = d, h = d,
        color = color or T.c.green, radius = math.floor(d / 2),
    })
    M.glass(obj, color or T.c.green, opacity or 255)
    return obj
end

return M
