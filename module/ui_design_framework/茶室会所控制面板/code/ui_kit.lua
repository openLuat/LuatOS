--[[
小组件：圆钮 / 开关 / 档位刻度段 / 胶囊 / 竖条
全部走 ui_widget 原语；只提供"改值"方法，不做显隐（I2）
]]

local T = require "ui_theme"
local W = require "ui_widget"
local CFG = require "app_config"

local K = {}

--------------------------------------------------------------------------
-- 圆钮：直径 d 的圆容器 + shape 画 − / +
-- shape 不传回调，点击由容器 on_click 与 ui_touch 兜底两条通路覆盖
--------------------------------------------------------------------------
function K.round_btn(parent, cfg)
    local d = cfg.d or 42
    local box = W.box(parent, {
        x = cfg.x, y = cfg.y, w = d, h = d, radius = d // 2,
        color = cfg.bg or T.c.btn, border_width = 0,
        on_click = cfg.on_click, tag = cfg.tag or "rbtn",
    })
    local cx = d // 2
    local half = math.max(5, d // 5)
    local col = cfg.color or T.c.text
    local items = {
        { type = "line", x1 = cx - half, y1 = cx, x2 = cx + half, y2 = cx,
          color = col, width = 2, opacity = 255 },
    }
    if cfg.icon == "plus" then
        items[#items + 1] = { type = "line", x1 = cx, y1 = cx - half, x2 = cx, y2 = cx + half,
                              color = col, width = 2, opacity = 255 }
    end
    W.shape(box, { x = 0, y = 0, w = d, h = d, items = items, tag = (cfg.tag or "rbtn") .. "-ic" })
    -- 高亮层必须在图标之后建，否则被图标压住
    W.hl(box, d // 2, cfg.tag or "rbtn")
    return box
end

--------------------------------------------------------------------------
-- 开关：52×28 轨道 + 22×22 旋钮
-- 内容区 52×28 → 旋钮开 27..49、关 3..25，两端各留 3
--------------------------------------------------------------------------
K.SW_W, K.SW_H, K.SW_KNB = 52, 28, 22

function K.switch(parent, cfg)
    local on = cfg.on and true or false
    local tag = cfg.tag or "sw"
    local track = W.box(parent, {
        x = cfg.x, y = cfg.y, w = K.SW_W, h = K.SW_H, radius = K.SW_H // 2,
        color = on and T.c.gold or T.c.track, border_width = 0,
        on_click = cfg.on_click, tag = tag,
    })
    local knob = W.box(track, {
        x = on and 27 or 3, y = 3, w = K.SW_KNB, h = K.SW_KNB, radius = K.SW_KNB // 2,
        color = T.c.knob, border_width = 0, tag = tag .. "-knob",
    })
    W.hl(track, K.SW_H // 2, tag)

    local hd = { track = track, knob = knob, on = on }
    function hd.set(v)
        v = v and true or false
        if hd.on == v then return end
        hd.on = v
        if track then pcall(function() track:set_color(v and T.c.gold or T.c.track, 255) end) end
        if knob then pcall(function() knob:set_pos(v and 27 or 3, 3) end) end
    end
    return hd
end

--------------------------------------------------------------------------
-- 档位刻度段：10 段等宽矩形，一个 shape 一条（对象数恒定，P3）
--------------------------------------------------------------------------
function K.seg_items(n, level, sw, sh, gap, on_color, off_color)
    local items = {}
    for i = 1, n do
        local x = (i - 1) * (sw + gap)
        local on = i <= level
        local col = on and on_color or off_color
        items[#items + 1] = {
            type = "rect", x = x, y = 0, w = sw, h = sh, radius = math.min(3, sh // 2),
            color = col, width = 0, fill = true, fill_color = col, fill_opacity = 255,
        }
    end
    return items
end

function K.segs(parent, cfg)
    local n = cfg.count or CFG.MAX_LEVEL
    local sw, sh, gap = cfg.w, cfg.h, cfg.gap or 2
    local total = n * sw + (n - 1) * gap
    local on_col = cfg.on_color or T.c.gold
    local off_col = cfg.off_color or T.c.seg_off
    local level = cfg.level or 0
    local shape = W.shape(parent, {
        x = cfg.x, y = cfg.y, w = total, h = sh,
        items = K.seg_items(n, level, sw, sh, gap, on_col, off_col),
        tag = cfg.tag or "segs",
    })
    local hd = { shape = shape, level = level, total = total }
    function hd.set(v)
        v = math.max(0, math.min(n, v))
        if hd.level == v then return end
        hd.level = v
        if shape then
            pcall(function()
                shape:set_items(K.seg_items(n, v, sw, sh, gap, on_col, off_col))
            end)
        end
    end
    return hd
end

--------------------------------------------------------------------------
-- 胶囊：透明容器 + 文案（用于"卡片状态""快捷档位"）
--------------------------------------------------------------------------
function K.pill(parent, cfg)
    local h = cfg.h or 22
    local bw = cfg.border and 1 or 0
    local tx = cfg.text_x or 0
    local box = W.box(parent, {
        x = cfg.x, y = cfg.y, w = cfg.w, h = h, radius = h // 2,
        color = cfg.bg or T.c.btn, color_opacity = cfg.bg_opa or 200,
        border_width = bw, border_color = cfg.border_color or T.c.line,
        on_click = cfg.on_click, tag = cfg.tag or "pill",
    })
    if cfg.dot_color then
        W.box(box, {
            x = cfg.dot_x or 10, y = (h - 5) // 2, w = 5, h = 5, radius = 3,
            color = cfg.dot_color, border_width = 0, tag = (cfg.tag or "pill") .. "-dot",
        })
    end
    -- 默认文字宽必须扣掉描边（内容区 = w - 2*bw），否则带描边的胶囊必然触发收敛告警
    local lbl = W.text(box, {
        x = tx, y = (h - (cfg.size or CFG.FONT.mini) - 3) // 2,
        w = cfg.text_w or (cfg.w - 2 * bw - tx),
        h = (cfg.size or CFG.FONT.mini) + 3,
        text = cfg.text or "", size = cfg.size or CFG.FONT.mini,
        color = cfg.color or T.c.dim,
        align = cfg.align or airui.TEXT_ALIGN_LEFT, tag = (cfg.tag or "pill") .. "-t",
    })
    if cfg.hl then W.hl(box, h // 2, cfg.tag or "pill") end
    return box, lbl
end

--------------------------------------------------------------------------
-- 竖条（左轴选中指示）：2×26
--------------------------------------------------------------------------
function K.tick(parent, x, y, h, color)
    return W.box(parent, {
        x = x, y = y, w = 2, h = h, radius = 1,
        color = color, border_width = 0, tag = "rail-tick",
    })
end

return K
