--[[
@module  ui_widget
@summary AirUI 安全原语（卡片 / 文字 / 贴图 / 热区 / 开关 / 胶囊 / 进度条）
@version 1.0.0
@note 本文件是「唯一允许创建控件的入口」，页面只通过这里出控件。四条硬约束来自真机：
      1) 热区只能是「透明 container + Lua 闭包」（airui.button 有清不掉的 2px 描边，
         还有只 hide 不 open 的历史问题）；
      2) 容器一律 border_width = 0 且不传 border_color（描边不吃 opacity，会留幽灵框）；
      3) 显隐只改 alpha + 关命中，禁止 hide()/open()；
      4) label 文字顶部对齐，居中必须让 h = 字号 + 3（hzfont line_height = size + 3）。
]]
local T = require "ui_theme"
local C = T.c
local M = {}

-- ==================== 基础容器 ====================
--- 纯色圆角容器（无描边）
--- @param scrollable boolean|nil 传 false 可关掉容器滚动（整页切换的父容器必须关，
---        否则子控件移出边界会画滚动条；装内容的容器保持默认，靠坐标预算避免溢出）
function M.box(parent, x, y, w, h, color, radius, scrollable)
    local cfg = {
        parent = parent, x = x, y = y, w = w, h = h,
        color = color or C.card, radius = radius or 0, border_width = 0,
    }
    if scrollable ~= nil then cfg.scrollable = scrollable end
    return airui.container(cfg)
end

--- 唯一的透明度入口（兼容 set_color(color, opa) 与不带 opa 的固件）
function M.glass(obj, color, opa)
    if not obj then return end
    if not pcall(function() obj:set_color(color, opa) end) then
        pcall(function() obj:set_color(color) end)
    end
end

--- 颜色线性插值（纯算术，兼容无位运算的固件）
function M.mix(c1, c2, t)
    local function rgb(c)
        return math.floor(c / 65536) % 256, math.floor(c / 256) % 256, c % 256
    end
    local r1, g1, b1 = rgb(c1)
    local r2, g2, b2 = rgb(c2)
    local function lerp(a, b) return math.floor(a + (b - a) * t + 0.5) end
    return lerp(r1, r2) * 65536 + lerp(g1, g2) * 256 + lerp(b1, b2)
end

--- 软补间：默认即时模式直落终态（MO.instant）
function M.tween(frames, setter, done)
    if T.motion.instant or not T.motion.enabled then
        setter(1)
        if done then done() end
        return
    end
    local i = 0
    local function step()
        i = i + 1
        setter(i / frames)
        if i < frames then
            sys.timerStart(step, 30)
        elseif done then
            done()
        end
    end
    sys.timerStart(step, 30)
end

--- 延迟执行（事件回调里不要直接销毁/重建自己）
function M.defer(fn, ms)
    return sys.timerStart(function()
        local ok, err = pcall(fn)
        if not ok then log.error("ui", "defer 执行失败", tostring(err)) end
    end, ms or 30)
end

-- ==================== 文字 ====================
--- 普通文字：行长不足会向下探出父容器，这里统一按 1.75 倍兜底
function M.text(parent, cfg)
    local size = cfg.size or T.f.body
    local h = math.max(cfg.h or 28, math.ceil(size * 1.75) + 2)
    return airui.label({
        parent = parent, text = cfg.text or "", x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or 120, h = h, font_size = size,
        color = cfg.color or C.ink, align = cfg.align or airui.TEXT_ALIGN_LEFT,
    })
end

--- 垂直居中文字：hzfont 真实行高 = 字号 + 3，label 高度取行高再按容器高居中
function M.text_mid(parent, cfg)
    local size = cfg.size or T.f.body
    local th = size + 3
    local y = (cfg.y or 0) + math.max(0, math.floor(((cfg.h or th) - th) / 2))
    return airui.label({
        parent = parent, text = cfg.text or "", x = cfg.x or 0, y = y,
        w = cfg.w or 120, h = th, font_size = size,
        color = cfg.color or C.ink, align = cfg.align or airui.TEXT_ALIGN_LEFT,
    })
end

--- LVGL symbol 图标（不依赖 hzfont 是否覆盖特殊符号）
function M.icon(parent, cfg)
    local size = cfg.size or 20
    return airui.label({
        parent = parent, symbol = cfg.symbol, x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or (size + 8), h = cfg.h or (size + 6), font_size = size,
        color = cfg.color or C.ink2, align = airui.TEXT_ALIGN_CENTER,
    })
end

-- ==================== 卡片 ====================
--- 白卡 + 假投影（container 不解析 shadow 参数，只能用偏移色块近似）
--- 返回值把 root 与 inner 分开：子控件坐标相对 inner（= 卡片内容区）
function M.card(parent, cfg)
    local off = cfg.shadow == false and 0 or T.motion.shadow
    local w, h = cfg.w, cfg.h
    local root = M.box(parent, cfg.x, cfg.y, w, h + off, -1, 0)
    if off > 0 then
        local sh = M.box(root, 0, off, w, h, C.shadow, cfg.radius or T.r.card)
        M.glass(sh, C.shadow, cfg.shadow_opa or 60)
    end
    local inner = M.box(root, 0, 0, w, h, cfg.color or C.card, cfg.radius or T.r.card)
    local handle = { root = root, inner = inner, x = cfg.x, y = cfg.y, w = w, h = h }
    return handle
end

-- ==================== 贴图 ====================
local assets = nil
local function assets_mod()
    if assets == nil then
        -- require 用字面量：打包工具按静态依赖裁剪，动态 require 会被漏掉
        local ok, m = pcall(function() return require "assets" end)
        assets = ok and m or false
        if not ok then log.warn("ui_widget", "assets 模块不可用，全部走几何占位", tostring(m)) end
    end
    return assets or nil
end

--- 卡通贴图：取不到图就画同尺寸几何占位，绝不留空框
--- fit 必须显式传 "contain"：airui.image 的 fit 默认是 center，即「不缩放、只居中」，
--- 此时 w/h 只当裁剪框用（72px 的 Twemoji 放进 28px 的胶囊会被截成一块纯色）。
--- @return userdata obj, boolean is_image
function M.sticker(parent, cfg)
    local A = assets_mod()
    local path = A and A.resolve(cfg.name) or nil
    if path then
        local ok, obj = pcall(airui.image, {
            parent = parent, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h, src = path,
            fit = "contain",
        })
        if ok and obj then return obj, true end
        log.warn("ui_widget", "贴图创建失败，退化为几何占位", cfg.name, path)
    end
    -- 几何占位：圆角底 + 圆点，颜色跟主题走，和真贴图尺寸一致
    local box = M.box(parent, cfg.x, cfg.y, cfg.w, cfg.h, C.on, math.floor(cfg.w / 4))
    local dot = M.box(box, math.floor(cfg.w * 0.28), math.floor(cfg.h * 0.28),
        math.floor(cfg.w * 0.44), math.floor(cfg.h * 0.44), C.pri2, math.floor(cfg.w * 0.22))
    M.glass(dot, C.pri2, 200)
    return box, false
end

--- 换图（角色切换只换 src，不重建控件）
function M.set_image(obj, name)
    if not obj then return end
    local A = assets_mod()
    local path = A and A.resolve(name) or nil
    if not path then return end
    pcall(function() obj:set_src(path) end)
end

--- 装饰贴纸：可带呼吸（只有真正的 image 才登记，几何占位不登记）
function M.deco(parent, cfg)
    local obj, isimg = M.sticker(parent, cfg)
    if isimg and cfg.twinkle then M.twinkle(obj, cfg.lo or 150) end
    return obj, isimg
end

-- ==================== 光晕 / 呼吸 ====================
--- 光晕：真机没有 blur，用大圆 + 低透明近似（效果稿的 .icon-halo / .glow）
function M.halo(parent, cfg)
    local d = cfg.d
    local o = M.box(parent, cfg.x, cfg.y, d, d, cfg.color or C.band1, math.floor(d / 2))
    M.glass(o, cfg.color or C.band1, cfg.opa or 90)
    return o
end

--- 呼吸：装饰贴纸在 500ms 心跳里切两档透明度（不做逐帧动画）
--- 只登记 airui.image（label/container 没有 set_opacity）
local twinkles = {}
function M.twinkle(obj, lo)
    if not obj then return end
    twinkles[#twinkles + 1] = { obj = obj, lo = lo or 150, hi = 255, dim = true }
end

--- 主题重建时清空登记，避免碰到已销毁的图片对象
function M.clear_twinkle()
    twinkles = {}
end

function M.tick_twinkle()
    for i = #twinkles, 1, -1 do
        local t = twinkles[i]
        t.dim = not t.dim
        local ok = pcall(function() t.obj:set_opacity(t.dim and t.lo or t.hi) end)
        if not ok then table.remove(twinkles, i) end
    end
end

-- ==================== 热区 ====================
--- 透明 container 热区：按下即时提亮 + 目标下压 2px，90ms 复原。
--- 命中开关是纯 Lua 闭包，不依赖固件方法（隐藏态点它无效，不会吃掉下层触摸）。
---
--- 控件「是否已销毁」不能用 obj:is_destroyed() 判断：本固件里它对活着的 container 也返回 true，
--- 会让所有点击直接失效（实测 6 次点击全部被挡）。改用纯 Lua 的「代次」：
--- 主题切换整页销毁前 epoch + 1，旧的 90ms 回弹定时器发现代次变了就自己退出，
--- 既不会碰已销毁对象，也不依赖任何固件方法。
local epoch = 0
function M.bump_epoch() epoch = epoch + 1 end
function M.epoch() return epoch end

function M.press(parent, cfg)
    local target, tx, ty = cfg.target, cfg.tx, cfg.ty
    local enabled = true
    local flash = cfg.flash or 0xFFFFFF
    local my = epoch                                   -- 本热区所属代次
    local hit = airui.container({
        parent = parent, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
        color = flash, color_opacity = 0,
        radius = cfg.radius or T.r.card, border_width = 0,
        on_click = function()
            if not enabled or my ~= epoch then return end
            M.glass(hit, flash, cfg.flash_opa or 46)
            if target then pcall(function() target:set_pos(tx, ty + T.motion.press_dy) end) end
            sys.timerStart(function()
                if my ~= epoch then return end          -- 期间整页被销毁过，直接放弃回弹
                M.glass(hit, flash, 0)
                if target then pcall(function() target:set_pos(tx, ty) end) end
            end, T.motion.press_ms)
            if cfg.on_click then
                local ok, err = pcall(cfg.on_click)
                if not ok then log.error("ui_widget", "点击回调异常", tostring(err)) end
            end
        end,
    })
    M.glass(hit, flash, 0)
    local handle = { obj = hit }
    function handle.set_enabled(v) enabled = v and true or false end
    return handle
end

-- ==================== 开关（胶囊滑块） ====================
function M.switch(parent, cfg)
    local w, h = cfg.w or 60, cfg.h or 34
    local kd = h - 8
    local on = cfg.on and true or false
    local track = M.box(parent, cfg.x, cfg.y, w, h, on and C.pri or C.off, math.floor(h / 2))
    M.glass(track, on and C.pri or C.off, 255)
    local knob = M.box(track, on and (w - kd - 4) or 4, 4, kd, kd, C.white, math.floor(kd / 2))
    M.glass(knob, C.white, 255)

    local handle = { track = track, knob = knob, x = cfg.x, y = cfg.y, w = w, h = h }
    function handle.set(v)
        local nv = v and true or false
        if nv == on then return end
        on = nv
        pcall(function() knob:set_pos(on and (w - kd - 4) or 4, 4) end)
        M.glass(track, on and C.pri or C.off, 255)
    end
    function handle.get() return on end
    if cfg.tappable ~= false then
        M.press(parent, {
            x = cfg.x, y = cfg.y, w = w, h = h, radius = math.floor(h / 2),
            on_click = cfg.on_click,
        })
    end
    return handle
end

-- ==================== 胶囊 / 档位 ====================
function M.chip(parent, cfg)
    local w, h = cfg.w, cfg.h or 40
    local radius = math.floor(h / 2)
    local box = M.box(parent, cfg.x, cfg.y, w, h, cfg.off_bg or C.off, radius)
    M.glass(box, cfg.off_bg or C.off, 255)
    local lbl = M.text_mid(parent, {
        text = cfg.text, x = cfg.x, y = cfg.y, w = w, h = h,
        size = cfg.size or T.f.sub, color = cfg.off_fg or C.ink2,
        align = airui.TEXT_ALIGN_CENTER,
    })
    local active = nil
    local handle = { box = box, lbl = lbl }
    function handle.set_active(v)
        local nv = v and true or false
        if nv == active then return end
        active = nv
        local bg = nv and C.pri or (cfg.off_bg or C.off)
        local fg = nv and C.white or (cfg.off_fg or C.ink2)
        M.glass(box, bg, 255)
        pcall(function() lbl:set_color(fg) end)
    end
    if cfg.on_click then
        M.press(parent, {
            x = cfg.x, y = cfg.y, w = w, h = h, radius = radius,
            on_click = cfg.on_click,
        })
    end
    handle.set_active(cfg.active)
    return handle
end

-- ==================== 进度条 ====================
--- container 没有 set_size，改变宽度只能靠 airui.bar（LVGL bar，set_value 改进度）。
--- bar 不支持时退化为静态轨道，进度用文字表达，界面不崩。
function M.bar(parent, cfg)
    local w, h = cfg.w, cfg.h or 16
    local r = math.floor(h / 2)
    local ok, obj = pcall(airui.bar, {
        parent = parent, x = cfg.x, y = cfg.y, w = w, h = h,
        min = 0, max = 100, value = math.floor(cfg.value or 0),
        radius = r, bg_color = cfg.track or C.track,
        indicator_color = cfg.fill or C.pri, border_width = 0,
    })
    local handle = { obj = ok and obj or nil }
    function handle.set(pct)
        pct = math.max(0, math.min(100, tonumber(pct) or 0))
        handle.pct = pct
        if handle.obj then pcall(function() handle.obj:set_value(math.floor(pct)) end) end
    end
    -- 填充色随当前色点变（效果稿里亮度条是选中色）
    function handle.set_color(c)
        if not c then return end
        if handle.obj then pcall(function() handle.obj:set_indicator_color(c) end) end
    end
    if not (ok and obj) then
        log.warn("ui_widget", "airui.bar 不可用，进度条退化为静态条", cfg.tag or "")
        handle.track = M.box(parent, cfg.x, cfg.y, w, h, cfg.track or C.off, r)
        M.glass(handle.track, cfg.track or C.off, 255)
    end
    handle.pct = cfg.value or 0
    return handle
end

-- ==================== 圆角按钮 ====================
--- 文字/符号按钮：底 + 文字 + 热区（内部不用 airui.button）
function M.button(parent, cfg)
    local w, h = cfg.w, cfg.h
    local radius = cfg.radius or math.floor(h / 2)
    local box = M.box(parent, cfg.x, cfg.y, w, h, cfg.bg or C.on, radius)
    M.glass(box, cfg.bg or C.on, 255)
    if cfg.symbol then
        M.icon(parent, {
            symbol = cfg.symbol, x = cfg.x, y = cfg.y, w = w, h = h,
            size = cfg.size or 22, color = cfg.fg or C.pri,
        })
    else
        M.text_mid(parent, {
            text = cfg.text or "", x = cfg.x, y = cfg.y, w = w, h = h,
            size = cfg.size or T.f.body, color = cfg.fg or C.pri,
            align = airui.TEXT_ALIGN_CENTER,
        })
    end
    local hit = M.press(parent, {
        x = cfg.x, y = cfg.y, w = w, h = h, radius = radius, tag = cfg.tag,
        target = box, tx = cfg.x, ty = cfg.y, on_click = cfg.on_click,
    })
    return box, hit
end

return M
