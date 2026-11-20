--[[
@module  ui_widget
@summary 会议室门牌 · AirUI 安全原语（玻璃卡 / 透明热区 / 胶囊 chip / 数字键盘 / 进度条）
@version 1.0.0
@note 1) AirUI 没有背景模糊，浮层用「半透明叠层 + 1px 高光 + 假投影」近似；
      2) 显隐只用透明度 + 清文字 + 关命中，绝不用 hide()/open()（真机 open() 恢复不回来）；
      3) 容器不传 border_color 就没有描边；需要描边统一由 theme.glass.card_edge 开关；
      4) 任何控件（含动画全程）不得探出父容器内容区，否则 AirUI 会画滚动条。
]]
local T = require "ui_theme"
local C, G, MO = T.c, T.glass, T.motion
local M = { motion_enabled = true }

-- ==================== 基础 ====================
function M.glass(obj, color, opa)
    if not obj then return end
    if not pcall(function() obj:set_color(color, opa) end) then
        pcall(function() obj:set_color(color) end)      -- 个别固件不支持第二个参数
    end
end

function M.mix(c1, c2, t)                               -- 颜色线性插值（纯算术）
    local function rgb(c)
        return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
    end
    local r1, g1, b1 = rgb(c1)
    local r2, g2, b2 = rgb(c2)
    local function lerp(a, b) return math.floor(a + (b - a) * t + 0.5) end
    return lerp(r1, r2) * 65536 + lerp(g1, g2) * 256 + lerp(b1, b2)
end

-- 软补间：默认即时模式（MO.instant）直接落到终态，不建任何定时器
function M.tween(frames, setter, done)
    if MO.instant or not (M.motion_enabled and MO.enabled) then
        setter(1)
        if done then done() end
        return
    end
    local i = 0
    local function step()
        i = i + 1
        setter(i / frames)
        if i < frames then sys.timerStart(step, 20)
        elseif done then done() end
    end
    sys.timerStart(step, 20)
end

-- label 文本不会自动换行/截断，超宽会画到控件外面；中文 3 字节/字，这里按字截断
function M.clip(s, n)
    s = tostring(s or "")
    local maxb = n * 3
    if #s > maxb then s = s:sub(1, maxb) end
    return s
end

function M.set(lbl, txt)
    if lbl then pcall(function() lbl:set_text(txt or "") end) end
end

function M.color(lbl, c)
    if lbl then pcall(function() lbl:set_color(c) end) end
end

-- 单行文字：hzfont 真实行高 = 字号 + 3，声明 h 小于行高会向下探出父容器
function M.text(parent, cfg)
    local sz = cfg.size or T.f.body
    local h = math.max(cfg.h or 28, sz + 3)
    return airui.label({
        parent = parent, text = cfg.text or "", x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or 120, h = h, font_size = sz,
        color = cfg.color or C.text, align = cfg.align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 垂直居中文字：让 label 高度 = 真实行高，再按容器高度算 y，视觉中心才与卡片重合
function M.text_mid(parent, cfg)
    local size = cfg.size or T.f.body
    local th = size + 3
    local y = (cfg.y or 0) + math.max(0, math.floor(((cfg.h or th) - th) / 2))
    return airui.label({
        parent = parent, text = cfg.text or "", x = cfg.x or 0, y = y,
        w = cfg.w or 120, h = th, font_size = size,
        color = cfg.color or C.text, align = cfg.align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 图标：用 LVGL 内置 symbol 字体，不依赖 hzfont 是否覆盖 Unicode 符号
function M.icon(parent, cfg)
    local size = cfg.size or 20
    return airui.label({
        parent = parent, symbol = cfg.symbol, x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or (size + 6), h = cfg.h or (size + 6), font_size = size,
        color = cfg.color or C.text_dim,
    })
end

-- ==================== 玻璃卡片 ====================
-- 返回 { root, card(内容父容器), hl, sh, sweep() }
-- root 高 = h + shadow_off + 2：投影层不与容器底零余量贴合，避免底部一条长横线
function M.glass_card(cfg)
    local off, w, h = G.shadow_off, cfg.w, cfg.h
    local root = airui.container({ parent = cfg.parent, x = cfg.x, y = cfg.y,
        w = w, h = h + off + 2, color = -1, border_width = 0 })
    local sh = airui.container({ parent = root, x = 0, y = off, w = w, h = h,
        color = C.shadow, radius = T.r.card, border_width = 0 })
    M.glass(sh, C.shadow, G.shadow_opa)
    -- 描边宽度由 G.card_edge 控制；描边不吃透明度，背景透明后描边照样画（幽灵框来源）
    local card = airui.container({ parent = root, x = 0, y = 0, w = w, h = h,
        color = C.card, radius = T.r.card,
        border_color = (G.card_edge > 0) and C.edge or nil,
        border_width = G.card_edge or 0 })
    M.glass(card, C.card, G.card_opa)
    local hl = airui.container({ parent = card, x = 20, y = 1, w = w - 44, h = 2,
        color = C.hl, radius = 1, border_width = 0 })
    M.glass(hl, C.hl, G.hl_opa)
    local handle = { root = root, card = card, hl = hl, sh = sh, x = cfg.x, y = cfg.y }
    function handle.sweep()
        M.tween(4, function(t)
            local opa = G.hl_opa + (G.hl_sweep_opa - G.hl_opa) * math.sin(t * math.pi)
            M.glass(hl, C.hl, math.floor(opa))
        end, function()
            M.glass(hl, C.hl, G.hl_opa)                 -- 收尾落回常态，避免顶部留一条常亮线
        end)
    end
    return handle
end

-- ==================== 按下反馈层（透明容器热区） ====================
-- 不用 airui.button 做热区：button 默认 2px 描边清不掉、有 hide() 没 open()、
-- set_disabled 不稳。container：不传 border_color 就零描边，alpha 0 彻底不可见，
-- 命中开关用纯 Lua 闭包控制；点击反馈 = 提亮一档 + 目标下压 2px，90ms 复原。
function M.press_layer(parent, cfg)
    local target, tx, ty = cfg.target, cfg.tx, cfg.ty
    local glow = cfg.glow or 55                         -- 按下提亮强度：大块热区要调低，否则闪得刺眼
    local enabled = true
    local hit = airui.container({ parent = parent, x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, color = 0xFFFFFF, color_opacity = 0,
        radius = cfg.radius or T.r.panel, border_width = 0,
        on_click = function()
            if not enabled then return end
            M.glass(hit, 0xFFFFFF, glow)
            if target then pcall(function() target:set_pos(tx, ty + MO.press_dy) end) end
            sys.timerStart(function()
                M.glass(hit, 0xFFFFFF, 0)
                if target then pcall(function() target:set_pos(tx, ty) end) end
            end, 90)
            if cfg.on_click then cfg.on_click() end
        end })
    M.glass(hit, 0xFFFFFF, 0)                           -- 兜底：固件不认 color_opacity 时再压一次
    local handle = { obj = hit }
    function handle.set_disabled(a, b)                   -- 兼容点调用与冒号调用
        local v = (b ~= nil) and b or a
        enabled = not v
    end
    function handle.set_visible(a, b)
        local v = (b ~= nil) and b or a
        enabled = v and true or false
    end
    return handle
end

-- ==================== 胶囊 chip（单选组） ====================
function M.chip(parent, cfg)
    local off_c = cfg.off_color or C.chip_off
    local off_o = cfg.off_opa or G.tile_opa
    local off_t = cfg.off_tcolor or C.chip_off_t
    local on_c  = cfg.on_color or C.pri
    local on_o  = cfg.on_opa or 255
    local on_t  = cfg.on_tcolor or C.on_accent
    local radius = math.floor((cfg.h or 36) / 2)
    local box = airui.container({ parent = parent, x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, color = off_c, radius = radius, border_width = 0 })
    M.glass(box, off_c, off_o)                          -- 必须显式上透明度，container 默认 255
    local lbl = M.text_mid(parent, { text = cfg.text, x = cfg.x, y = cfg.y, w = cfg.w,
        h = cfg.h, size = cfg.size or T.f.mini, color = off_t, align = airui.TEXT_ALIGN_CENTER })
    local active = nil                                  -- nil 哨兵：首次 set_active 必须真上色
    local handle = { box = box, lbl = lbl }
    function handle.set_active(v)
        local nv = v and true or false
        if nv == active then return end
        local from_c = active and on_c or off_c
        local from_o = active and on_o or off_o
        local from_t = active and on_t or off_t
        active = nv
        local to_c = nv and on_c or off_c
        local to_o = nv and on_o or off_o
        local to_t = nv and on_t or off_t
        M.tween(3, function(t)
            M.glass(box, M.mix(from_c, to_c, t), math.floor(from_o + (to_o - from_o) * t))
            M.color(lbl, M.mix(from_t, to_t, t))
        end)
    end
    M.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        radius = radius, target = box, tx = cfg.x, ty = cfg.y, on_click = cfg.on_click })
    handle.set_active(cfg.active)
    return handle
end

-- ==================== 圆角按钮 ====================
function M.button(parent, cfg)
    local radius = cfg.radius or T.r.btn
    local color = cfg.color or C.pri
    local opa = cfg.opa or 255
    local box = airui.container({ parent = parent, x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, color = color, radius = radius, border_width = 0 })
    M.glass(box, color, opa)
    M.text_mid(parent, { text = cfg.text, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        size = cfg.size or T.f.body, color = cfg.tcolor or C.on_accent,
        align = airui.TEXT_ALIGN_CENTER })
    local press = M.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        radius = radius, target = box, tx = cfg.x, ty = cfg.y, on_click = cfg.on_click })
    return { box = box, press = press }
end

-- ==================== 进度条（shape 两段矩形，可刷新比例） ====================
-- container 没有 set_size，做不了可变的实心填充；shape:set_items 可以整组重画。
function M.bar(parent, cfg)
    local h, r = cfg.h or 8, math.floor((cfg.h or 8) / 2)
    local color = cfg.color or C.pri
    local function items_for(ratio, col)
        local fw = math.floor(cfg.w * ratio + 0.5)
        local items = {
            { type = "rect", x = 0, y = 0, w = cfg.w, h = h, radius = r, fill = true,
              fill_color = cfg.track_color or C.track, fill_opacity = cfg.track_opa or G.track_opa },
        }
        if fw > 0 then
            items[#items + 1] = { type = "rect", x = 0, y = 0, w = fw, h = h, radius = r,
                fill = true, fill_color = col or color, fill_opacity = 255 }
        end
        return items
    end
    -- 建组件时就要给一条合法图元，空 items 在部分固件上会创建失败（返回 nil，进度条整条丢失）
    local shape = M.shape(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = h,
        items = items_for(0, color) })
    local handle = {}
    function handle.set(ratio, col)
        if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
        if not shape then return end
        pcall(function() shape:set_items(items_for(ratio, col)) end)
    end
    return handle
end

-- ==================== 图形（旧固件可能没有 shape） ====================
function M.shape(parent, cfg)
    local ok, obj = pcall(function()
        cfg.parent = parent
        return airui.shape(cfg)
    end)
    if ok and obj then return obj end
    return nil
end

-- ==================== 数字键盘 ====================
-- 3x4 固定布局：1-9 / 清空 / 0 / 退格。按键回调上抛字符，由页面决定写到哪个输入框。
-- handle.set_visible(false)：底板 alpha 归零 + 清文字 + 关命中（不用 hide/open）。
function M.numpad(parent, cfg)
    local gap = cfg.gap or 10
    local kw = math.floor((cfg.w - gap * 2) / 3)
    local kh = math.floor((cfg.h - gap * 3) / 4)
    local labels = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "清空", "0", "退格" }
    local keys = {}
    local handle = { keys = keys }

    local function emit(k)
        if cfg.on_key then cfg.on_key(k) end
    end

    for i, k in ipairs(labels) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local x = cfg.x + col * (kw + gap)
        local y = cfg.y + row * (kh + gap)
        local action = (k == "清空" or k == "退格")
        local base_c = action and C.btn_bg or C.tile
        local base_o = action and 190 or G.tile_opa
        local box = airui.container({ parent = parent, x = x, y = y, w = kw, h = kh,
            color = base_c, radius = T.r.panel, border_width = 0 })
        M.glass(box, base_c, base_o)
        local lbl = M.text_mid(parent, { text = k, x = x, y = y, w = kw, h = kh,
            size = action and T.f.mini or 22,
            color = action and C.text_sub or C.text, align = airui.TEXT_ALIGN_CENTER })
        local hit = M.press_layer(parent, { x = x, y = y, w = kw, h = kh,
            radius = T.r.panel, target = box, tx = x, ty = y,
            on_click = function() emit(k) end })
        keys[#keys + 1] = { box = box, lbl = lbl, hit = hit, k = k,
                            c = base_c, o = base_o, action = action }
    end

    function handle.set_visible(v)
        for _, key in ipairs(keys) do
            if v then
                M.glass(key.box, key.c, key.o)
                M.set(key.lbl, key.k)
                key.hit.set_disabled(false)
            else
                M.glass(key.box, key.c, 0)
                M.set(key.lbl, "")
                key.hit.set_disabled(true)
            end
        end
    end
    return handle
end

-- ==================== 细节 ====================
function M.toast_in(lbl, msg)                           -- toast：颜色渐显（主色）
    M.set(lbl, msg)
    M.tween(3, function(t)
        M.color(lbl, M.mix(C.text_dim, C.pri, t))
    end)
end

return M
