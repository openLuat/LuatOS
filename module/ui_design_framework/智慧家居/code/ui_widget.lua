--[[
@module  ui_widget
@summary 玻璃拟态组件 + 隐性微动引擎
@version 1.0.0
@note 1) AirUI/LVGL 没有背景模糊，这里用「柔光底 + 半透明叠层 + 高光描边 + 双层假投影」近似；
      2) container 只有 on_click，按下态来自 airui.button 的 pressed 样式；
         老固件没有 button 组件时自动回退为 container + 点击后短反馈，界面不崩；
      3) 所有微动都是局部、短时、状态驱动，不做全屏/整卡持续动画。
]]
local T = require "ui_theme"
local C, G, MO = T.c, T.glass, T.motion
local M = { motion_enabled = true }

-- ==================== 基础 ====================
function M.glass(obj, color, opa)
    if not obj then return end
    if not pcall(function() obj:set_color(color, opa) end) then
        pcall(function() obj:set_color(color) end)       -- 个别固件不支持第二参数
    end
end

-- 注意：不要用 container:hide()/open() 做显隐。真机实测 hide() 生效但 open() 无法恢复
-- （调节条打开后一片空白），控件会被永久藏死。显隐一律用透明度（set_color + opa=0）：
-- 容器不传 border_color 就没有描边，alpha 0 时是真不可见；命中则用闭包开关控制。

function M.mix(c1, c2, t)                                -- 颜色线性插值（纯算术，兼容 Lua 5.1）
    local function rgb(c)
        return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
    end
    local r1, g1, b1 = rgb(c1)
    local r2, g2, b2 = rgb(c2)
    local function lerp(a, b) return math.floor(a + (b - a) * t + 0.5) end
    return lerp(r1, r2) * 65536 + lerp(g1, g2) * 256 + lerp(b1, b2)
end

-- 软补间：每 frame_ms 一帧，setter(t) 收到 0→1 的进度
-- MO.instant（默认开）或关动效时：直接落到终态，不建任何定时器 ——
-- 真机上逐帧 Lua 定时器会被其他任务抢占（帧间隔 20~60ms 抖动），且点击后动画
-- 排队执行造成「松手了还在动」的拖尾，观感廉价；交互反馈改为零延迟直落终态。
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
        if i < frames then sys.timerStart(step, MO.frame_ms)
        elseif done then done() end
    end
    sys.timerStart(step, MO.frame_ms)
end

-- label 实际行高约为字号的 1.75 倍且随文字自适应（超长不换行不截断），
-- 声明 h 小于实际行高会向下探出父容器内容区、触发滚动条（airui.md §4.2.1/4.2.13）。
-- 这里统一兜底：h = max(声明值, 字号×1.75 + 2px 余量)
function M.text(parent, cfg)
    local sz = cfg.size or T.f.body
    local h = math.max(cfg.h or 28, math.ceil(sz * 1.75) + 2)
    return airui.label({
        parent = parent, text = cfg.text or "", x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or 120, h = h, font_size = sz,
        color = cfg.color or C.text, align = cfg.align or airui.TEXT_ALIGN_LEFT,
        font_weight = cfg.weight,
    })
end

-- 垂直居中文字。AirUI label 的文字在控件内「顶部对齐」（text_align 只管水平），
-- 所以必须让 label 高度 = 真实行高，再按容器高度居中，视觉中心才与卡片中心重合。
-- hzfont 的真实行高在固件里是 size + 3（components/airui/src/font/lv_font_hzfont.c：
--   line_height = size + g_airui_hzfont_extra_leading，该常量 = 3）。
-- 之前用 1.75×字号 兜底（16 号字评成 30px）会让 label 虚高、文字贴顶，整体偏上；
-- label 底缘仍不探出 cfg.h，不触发容器滚动条（airui.md §4.2.13）。
function M.text_mid(parent, cfg)
    local size = cfg.size or T.f.body
    local th = size + 3
    local y = cfg.y + math.max(0, math.floor((cfg.h - th) / 2))
    return airui.label({
        parent = parent, text = cfg.text or "", x = cfg.x or 0, y = y,
        w = cfg.w or 120, h = th, font_size = size,
        color = cfg.color or C.text, align = cfg.align or airui.TEXT_ALIGN_LEFT,
        font_weight = cfg.weight,
    })
end

-- ==================== 小图标 ====================
-- 用 AirUI 内置的 LVGL symbol 字体画图标（官方 airui_label.lua 示例即用 symbol），
-- 不依赖 hzfont 是否覆盖 ☀ ▤ ❋ 这类 Unicode 符号。
-- symbol 本质是特殊字符串，可用 :set_text(airui.SYMBOL_xxx) 切换图标；
-- 亮 / 灭由调用方 :set_color(亮色 / 暗色) 控制，配合 set_vec_text 无额外开销。
function M.icon(parent, cfg)
    local size = cfg.size or 20
    return airui.label({
        parent = parent, symbol = cfg.symbol, x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or (size + 6), h = cfg.h or (size + 6), font_size = size,
        color = cfg.color or C.text_dim,
    })
end

-- ==================== 玻璃卡片 ====================
-- 返回 { root, card(内容父容器), hl(反光条), sh(投影层), sweep() }
-- cfg.fade_in = true：初始为近透明（配合 M.enter 上浮淡入入场）。
-- 注意：AirUI 容器滚动条固定 AUTO 且无法关闭（官方 airui.md §4.2.13），
--      子控件探出内容区 1px 就会画滚动条；所有位移类微动必须做边界预算，
--      保证动画全程不探出父容器内容区。
function M.glass_card(cfg)
    local off, w, h = G.shadow_off, cfg.w, cfg.h
    local root = airui.container({ parent = cfg.parent, x = cfg.x, y = cfg.y,
        w = w, h = h + off + 2, color = -1, border_width = 0 })  -- +2：投影层不与容器底零余量贴合
    local sh = airui.container({ parent = root, x = 0, y = off, w = w, h = h,
        color = C.shadow, radius = T.r.card, border_width = 0 })
    M.glass(sh, C.shadow, cfg.fade_in and 8 or G.shadow_opa)   -- 双层假投影（container 不解析 shadow 参数）
    -- 描边宽度由 G.card_edge 控制（0 = 无框线）。描边**不吃透明度**：卡片背景 opa 归零后
    -- 边框照样绘制，这正是「幽灵框」与「卡片底边一条横线」的来源。
    local card = airui.container({ parent = root, x = 0, y = 0, w = w, h = h,
        color = C.card, radius = T.r.card,
        border_color = (G.card_edge > 0) and C.edge or nil,
        border_width = G.card_edge or 0 })
    M.glass(card, C.card, cfg.fade_in and 6 or G.card_opa)
    local hl = airui.container({ parent = card, x = 20, y = 1, w = w - 44, h = 2,
        color = C.hl, radius = 1, border_width = 0 })
    M.glass(hl, C.hl, cfg.fade_in and 0 or G.hl_opa)
    local handle = { root = root, card = card, hl = hl, sh = sh, x = cfg.x, y = cfg.y }
    function handle.sweep()                                -- 交互时反光条轻微扫光
        M.tween(MO.sweep_fr, function(t)
            local opa = G.hl_opa + (G.hl_sweep_opa - G.hl_opa) * math.sin(t * math.pi)
            M.glass(hl, C.hl, math.floor(opa))
        end)
    end
    return handle
end

-- 模块入场：依次上浮 + 淡入（位移 enter_dy 像素 + 三层透明度渐显），只跑一次
-- 滚动条纪律（airui.md §4.2.13）：位移全程子控件不得探出父容器内容区。
-- 入场向下探出 enter_dy 像素，因此最底部卡片（Dock）root 底缘必须预留 ≥enter_dy 余量
-- （Dock.y=505，root 高 h+7，浮动峰值 505+83+10=598 ≤ 600 ✓）
function M.enter(handles)
    if MO.instant or not (M.motion_enabled and MO.enabled) then
        -- 即时模式：整屏一次呈现，不做错开排队（开机不拖尾）
        for _, c in ipairs(handles) do
            pcall(function() c.root:set_pos(c.x, c.y) end)
            M.glass(c.card, C.card, G.card_opa)
            M.glass(c.sh, C.shadow, G.shadow_opa)
            M.glass(c.hl, C.hl, G.hl_opa)
        end
        return
    end
    for i, c in ipairs(handles) do
        sys.timerStart(function()
            M.tween(MO.enter_fr, function(t)
                pcall(function() c.root:set_pos(c.x, c.y + MO.enter_dy * (1 - t)) end)
                M.glass(c.card, C.card, math.floor(6 + (G.card_opa - 6) * t))
                M.glass(c.sh, C.shadow, math.floor(8 + (G.shadow_opa - 8) * t))
                M.glass(c.hl, C.hl, math.floor(G.hl_opa * t))
            end, function()                          -- 收尾自愈：强制落回最终态
                pcall(function() c.root:set_pos(c.x, c.y) end)
                M.glass(c.card, C.card, G.card_opa)
                M.glass(c.sh, C.shadow, G.shadow_opa)
                M.glass(c.hl, C.hl, G.hl_opa)
            end)
        end, math.max(5, (i - 1) * MO.enter_gap))    -- 延迟最小 5ms，0 会导致 rtos 定时器创建失败
    end
end

-- ==================== 按下反馈层（透明容器热区） ====================
-- 不用 airui.button 做热区。button 有三个硬伤（真机逐条踩过）：
--   ① 默认 2px 描边，style 里的 border_width=0 未必生效 → 屏幕上留下一片「透明容器框」；
--   ② 有 hide() 却没有 open()/set_hidden(false) → 藏一次就永久不显示、也不再参与命中
--      （「调」怎么都点不开就是这个）；
--   ③ set_disabled 的调用约定不稳，禁用后可能再也解不开。
-- 改用 container：不传 border_color 就没有描边，color_opacity=0 彻底不可见，
-- 命中开关用纯 Lua 闭包控制，不依赖任何固件方法；点击反馈 = 提亮一档 + 目标下压 2px，90ms 复原。
function M.press_layer(parent, cfg)
    local target, tx, ty = cfg.target, cfg.tx, cfg.ty
    local enabled = true
    local hit = airui.container({ parent = parent, x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, color = 0xFFFFFF, color_opacity = 0,
        radius = cfg.radius or T.r.chip, border_width = 0,
        on_click = function()
            if not enabled then return end
            M.glass(hit, 0xFFFFFF, 55)                       -- 按下反馈：即时提亮
            if target then pcall(function() target:set_pos(tx, ty + MO.press_dy) end) end
            sys.timerStart(function()
                M.glass(hit, 0xFFFFFF, 0)
                if target then pcall(function() target:set_pos(tx, ty) end) end
            end, 90)
            if cfg.on_click then cfg.on_click() end
        end })
    M.glass(hit, 0xFFFFFF, 0)        -- 兜底：万一固件不认 color_opacity，这里再压一次 alpha=0
    local handle = { obj = hit }
    -- 兼容点调用与冒号调用两种写法（冒号会把 self 塞成第一个参数）
    function handle.set_disabled(a, b)
        local v = (b ~= nil) and b or a
        enabled = not v
    end
    function handle.set_visible(a, b)
        local v = (b ~= nil) and b or a
        enabled = v and true or false
    end
    return handle
end

local function container(parent, x, y, w, h, color, radius)
    return airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color, radius = radius, border_width = 0 })
end

-- ==================== 胶囊开关（滑块缓动） ====================
function M.switch(parent, cfg)
    local w, h, kd = cfg.w or 62, cfg.h or 32, (cfg.h or 32) - 8
    local on = cfg.on and true or false
    local track = container(parent, cfg.x, cfg.y, w, h, C.sw_off, math.floor(h / 2))
    M.glass(track, on and (cfg.on_color or C.sw_on) or C.sw_off, on and 255 or T.o.sw_off)
    local knob = container(track, 0, 4, kd, kd, C.knob, math.floor(kd / 2))
    local x0, x1 = 4, w - kd - 4
    local function put(x) pcall(function() knob:set_pos(x, 4) end) end
    put(on and x1 or x0)
    local handle = { track = track, knob = knob }
    local function render(from, to, cfrom, cto, notify)
        M.tween(MO.knob_fr, function(t)
            put(math.floor(from + (to - from) * t + 0.5))
            M.glass(track, M.mix(cfrom, cto, t), math.floor(T.o.sw_off + (255 - T.o.sw_off) * (on and t or 1 - t)))
        end)
        if notify ~= false and cfg.on_change then cfg.on_change(on) end  -- 仅内部同步传 false 时静默
    end
    function handle.set(v, notify)
        local nv = v and true or false
        if nv == on then return end
        local from, cfrom = on and x1 or x0, on and (cfg.on_color or C.sw_on) or C.sw_off
        on = nv
        local to, cto = on and x1 or x0, on and (cfg.on_color or C.sw_on) or C.sw_off
        render(from, to, cfrom, cto, notify)
    end
    function handle.get() return on end
    function handle.toggle() handle.set(not on) end
    M.press_layer(parent, { x = cfg.x, y = cfg.y, w = w, h = h, radius = math.floor(h / 2),
        target = track, tx = cfg.x, ty = cfg.y,
        on_click = function() handle.toggle() end })
    return handle
end

-- ==================== 圆角按钮（±） ====================
function M.button(parent, cfg)
    local box = container(parent, cfg.x, cfg.y, cfg.w, cfg.h, cfg.color or C.btn_bg, 12)
    M.glass(box, cfg.color or C.btn_bg, 230)
    M.text_mid(parent, { text = cfg.text, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        size = cfg.size or 26, color = 0xFFFFFF, align = airui.TEXT_ALIGN_CENTER })
    M.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h, radius = 12,
        target = box, tx = cfg.x, ty = cfg.y, on_click = cfg.on_click })
    return box
end

-- ==================== 图形 / 图表（旧固件可能没有这两个组件） ====================
-- airui.shape：line/circle/ellipse/rect 多图元，可虚线、可填充，坐标相对组件左上角
-- airui.chart：折线/柱状，支持渐变填充、网格、多系列
-- 两者都不可用时返回 nil，由调用方回退到容器拼的静态图形。
function M.shape(parent, cfg)
    local ok, obj = pcall(function()
        cfg.parent = parent
        return airui.shape(cfg)
    end)
    if ok and obj then return obj end
    return nil
end

function M.chart(parent, cfg)
    local ok, obj = pcall(function()
        cfg.parent = parent
        return airui.chart(cfg)
    end)
    if ok and obj then return obj end
    return nil
end

-- ==================== 档位 chip ====================
function M.chip(parent, cfg)
    local off_c = cfg.off_color or C.chip_off
    local off_o = cfg.off_opa or T.o.chip
    local off_t = cfg.off_tcolor or C.chip_off_t
    local on_c  = cfg.on_color or C.chip_on
    local on_o  = cfg.on_opa or 255
    local on_t  = cfg.on_tcolor or C.chip_on_t
    local radius = math.floor(cfg.h / 2)
    local box = container(parent, cfg.x, cfg.y, cfg.w, cfg.h, off_c, radius)
    M.glass(box, off_c, off_o)                      -- 必须显式上透明度：container 创建默认 255 不透明
    local lbl = M.text_mid(parent, { text = cfg.text, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        size = T.f.sub, color = off_t, align = airui.TEXT_ALIGN_CENTER })
    local active = nil                              -- nil = 未初始化：首次 set_active 必须真上色，
                                                    -- 否则 set_active(false) 会被「无变化」提前返回，
                                                    -- 底板停在纯白不透明（房间 Tab 太白的原因）
    local handle = {}
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
            pcall(function() lbl:set_color(M.mix(from_t, to_t, t)) end)
        end)
    end
    M.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        radius = radius, target = box, tx = cfg.x, ty = cfg.y,
        on_click = cfg.on_click })
    handle.set_active(cfg.active)
    handle.box = box
    return handle
end

-- ==================== 细节微动 ====================
function M.temp_pulse(lbl)                                -- 数值刷新：短暂高亮后回原色
    if not lbl then return end
    M.tween(MO.glow_fr, function(t)
        local k = math.sin(t * math.pi)
        pcall(function() lbl:set_color(M.mix(C.text, C.glow, k * 0.8)) end)
    end)
end

function M.toast_in(lbl, msg)                             -- toast：颜色渐显（青色主色）
    pcall(function() lbl:set_text(msg) end)
    M.tween(3, function(t)
        pcall(function() lbl:set_color(M.mix(C.text_dim, C.pri, t)) end)
    end)
end

return M
