--[[
@module  ui_widget
@summary 玻璃拟态组件（容器 / 文字 / 图标 / 玻璃卡 / 热区 / 档位 chip / 进度条 / 分段圆环 / 图片）
@version 1.0.0
@note 1) AirUI 没有背景模糊，这里用「半透明玻璃叠层 + 假投影 + 顶部高光条」近似；
      2) 不用 container:hide()/open() 做显隐：真机 hide 生效但 open 恢复不回来，
         显隐一律走 set_color(color,0) + 清文字 + 关命中（闭包开关）；
      3) 不用 airui.button 做热区：默认 2px 描边清不掉、set_disabled 不稳，
         统一用透明 container + 闭包，按下即时提亮 90ms；
      4) 描边不吃透明度，所以「选中边框」不做动态描边，改用底色 / 竖条 / 角标表达；
      5) label 行高在 hzfont 里是 size+3，所有文字高度按此兜底，避免向下探出触发滚动条。
]]
local T = require "ui_theme"
local C, G = T.c, T.glass
local M = {}

-- ==================== 基础 ====================
function M.glass(obj, color, opa)
    if not obj then return end
    if not pcall(function() obj:set_color(color, opa) end) then
        pcall(function() obj:set_color(color) end)
    end
end

-- ==================== 颜色登记（主题热切换用） ====================
-- 每个绘制对象登记「创建时用的颜色」，切主题时按 旧色值→新色值 批量改色，
-- 避免整页销毁重建（重建 240 个控件约 35ms + 一帧全屏重绘）。
local REG
local HL = {}                                    -- 玻璃卡顶部高光条（切主题时要改透明度）
local THEME_HOOKS = {}                           -- 切主题时要重算的“计算色”（渐变线等）
function M.reg_reset() REG = {}; HL = {}; THEME_HOOKS = {} end

-- 注册一个“切主题时重算”的回调（用于透明度算出来的渐隐线等）
function M.on_theme(fn)
    if type(fn) == "function" then THEME_HOOKS[#THEME_HOOKS + 1] = fn end
end

function M.apply_theme_hooks()
    for _, fn in ipairs(THEME_HOOKS) do pcall(fn) end
end
function M.reg_count() return REG and #REG or 0 end

-- okey：透明度令牌名（如 "surface3_opa"）；ckey：颜色令牌名（如 "card"）。
-- 只用「旧色值→新色值」映射是不可靠的：晨曦白下 card / pkg_off / chip_off 都是 #FFFFFF，
-- 反查会撞车（曾导致夜青下卡片不变色）。有令牌名时直接按名字取新值。
local function reg(kind, obj, color, opa, okey, ckey)
    if not REG or not obj or type(color) ~= "number" then return end
    REG[#REG + 1] = { k = kind, o = obj, c = color, a = opa, ok = okey, ck = ckey }
end

-- 按令牌名取当前主题的颜色（"__white" 表示两套主题都是纯白）
local function tok_color(name)
    if not name then return nil end
    if name == "__white" then return 0xFFFFFF end
    local v = C[name]
    if type(v) ~= "number" then v = G[name] end
    if type(v) == "number" then return v end
    return nil
end

-- 登记水位：临时界面（toast / 菜单 / 弹层 / 列表重建）销毁前回退到这里，
-- 避免表里残留已销毁对象（否则改色时会刷 "access destroyed airui component"）
function M.reg_mark() return REG and #REG or 0 end

-- 记录 [m0+1 .. 当前] 这段索引；销毁该临时界面时只作废这些条目。
-- 不能用“截断回 m0”：临时界面可能是趁其它面板构建到一半时创建的（如工序列表在中栏里），
-- 截断会把之后创建、仍然活着的控件也一起丢掉（曾导致右栏切主题后不变色）。
function M.reg_group(m0)
    local idx = {}
    if not REG then return idx end
    for i = (m0 or 0) + 1, #REG do idx[#idx + 1] = i end
    return idx
end

function M.reg_kill(idx)
    if not REG or not idx then return end
    for _, i in ipairs(idx) do
        if REG[i] then REG[i].o = nil end          -- 置空，retint 时跳过
    end
end

-- 顶部高光条按当前主题的透明度重设
function M.apply_hl(opa)
    for _, o in ipairs(HL) do
        pcall(function() o:set_color(0xFFFFFF, opa) end)
    end
end

-- map: { [旧色值] = 新色值 }；返回实际改色的对象数
function M.retint(map)
    if not REG or not map then return 0 end
    local n = 0
    for i = 1, #REG do
        local e = REG[i]
        -- 自绘图元（W.shape）：颜色写在 items 里，逐项按映射表换色
        if e.o and e.k == "items" then
            n = n + 1
            local ni = {}
            for k, it in ipairs(e.items or {}) do
                local t = {}
                for kk, vv in pairs(it) do t[kk] = vv end
                if type(t.color) == "number" then t.color = map[t.color] or t.color end
                ni[k] = t
            end
            pcall(function() e.o:set_items(ni) end)
        elseif e.o then
            local nc = (e.ck and tok_color(e.ck) or map[e.c])
            if nc then
                n = n + 1
                e.c = nc                             -- 关键：登记值跟着更新，否则第二次切主题就找不到映射
                if e.ok and G[e.ok] then             -- 透明度令牌：换成新主题的数值
                    e.a = G[e.ok]
                end
                if e.k == "text" then
                    pcall(function() e.o:set_color(nc) end)
                elseif e.k == "bar" then
                    pcall(function() e.o:set_indicator_color(nc) end)
                elseif e.k == "shape" then
                    pcall(function()
                        e.o:set_items({ { type = "rect", x = 0, y = 0, w = e.w, h = e.h,
                            radius = e.r, width = 1, color = nc, opacity = e.a } })
                    end)
                else
                    pcall(function() e.o:set_color(nc, e.a) end)
                end
            end
        end
    end
    return n
end

-- 通用容器：统一 border_width，避免「幽灵框」。
-- 注意：container 创建后仅靠 set_color(c, opa) 有时不生效（底板仍透明），
-- 所以创建时就把 color_opacity 传进去，set_color 只作兜底。
function M.box(parent, x, y, w, h, color, radius, opa, border_color, border_width, okey, ckey)
    -- scrollable=false：LVGL 容器子控件超出 1px 就会画滚动条，这里统一关掉
    local obj = airui.container({ parent = parent, x = x, y = y, w = w, h = h,
        color = color, radius = radius or 0, color_opacity = opa,
        border_color = border_color, border_width = border_width or 0,
        scrollable = false })
    -- 只有半透明时才需要兜底 set_color（不透明时创建参数已经生效，重复设置只会多一次重绘）
    if opa ~= nil and opa < 255 then M.glass(obj, color, opa) end
    reg("box", obj, color, opa, okey, ckey)
    return obj
end

local function line_h(size) return size + 3 end

-- 单行文字（顶部对齐）。h 不足时按行高兜底
function M.text(parent, cfg)
    local size = cfg.size or T.f.sub
    local h = math.max(cfg.h or line_h(size), line_h(size))
    local col = cfg.color or C.text
    local obj = airui.label({ parent = parent, text = cfg.text or "", x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or 120, h = h, font_size = size,
        color = col, align = cfg.align or airui.TEXT_ALIGN_LEFT,
        font_weight = cfg.weight })
    reg("text", obj, col)
    return obj
end

-- 垂直居中文字：label 高度取真实行高，再按容器高度居中
function M.text_mid(parent, cfg)
    local size = cfg.size or T.f.sub
    local th = line_h(size)
    local y = (cfg.y or 0) + math.max(0, math.floor(((cfg.h or th) - th) / 2))
    local col = cfg.color or C.text
    local obj = airui.label({ parent = parent, text = cfg.text or "", x = cfg.x or 0, y = y,
        w = cfg.w or 120, h = th, font_size = size,
        color = col, align = cfg.align or airui.TEXT_ALIGN_LEFT,
        font_weight = cfg.weight })
    reg("text", obj, col)
    return obj
end

-- 1px 圆角描边：LVGL 的 container border 在圆角处会画成直角，改用 shape 描线。
-- 注意：shape 的描边以路径为中心，贴边绘制会有一半落在形状外被父容器裁掉，
-- 表现就是「边框断了一截」（浅色主题下尤其明显）。所以统一向内缩 1px。
function M.stroke(parent, x, y, w, h, radius, color, opa, okey, ckey)
    -- 描边颜色必须按令牌名取，不能靠「旧色值→新色值」反查：
    -- 晨曦白下 G.hair_color 与 C.text 同为 #2C2926，反查会命中 text，
    -- 切到夜青后边框变成近白色（等于消失）。这里按调用时的色值自动归类。
    if not ckey and type(color) == "number" then
        if G.chip_edge and color == G.chip_edge then ckey = "chip_edge"
        elseif color == G.hair_color then ckey = "hair_color"
        elseif color == C.danger then ckey = "danger"
        elseif color == C.pri then ckey = "pri"
        elseif color == C.ok then ckey = "ok"
        end
    elseif not ckey then
        ckey = "hair_color"                          -- 未传颜色时默认用 hair
    end
    local function items(c, o)
        return { { type = "rect", x = 0, y = 0, w = w, h = h, radius = radius,
            width = 1, color = c or G.hair_color, opacity = o or G.hair_opa } }
    end
    local ok, obj = pcall(function()
        return airui.shape({ parent = parent, x = x, y = y, w = w, h = h,
            items = items(color, opa) })
    end)
    if not (ok and obj) then return nil end
    if REG then
        REG[#REG + 1] = { k = "shape", o = obj, c = color or G.hair_color,
            a = opa or G.hair_opa, ok = okey, ck = ckey, w = w, h = h, r = radius }
    end
    local handle = { obj = obj }
    function handle.set(c, o)
        pcall(function() obj:set_items(items(c, o)) end)
    end
    return handle
end

-- 矢量图元（line/circle/rect/arc 组合），用于自绘图标
function M.shape(parent, cfg)
    local ok, obj = pcall(function()
        return airui.shape({ parent = parent, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
            items = cfg.items or {} })
    end)
    if not (ok and obj) then return nil end
    -- 图元颜色写在 items 里、不走 box/text 的登记，这里单独登记一份，
    -- 否则切主题后自绘图形（对号、水滴、主题图标）会保留旧主题的颜色
    if REG then
        local copy = {}
        for i, it in ipairs(cfg.items or {}) do
            local t = {}
            for k, v in pairs(it) do t[k] = v end
            copy[i] = t
        end
        REG[#REG + 1] = { k = "items", o = obj, items = copy }
    end
    return obj
end

-- 内置 symbol 图标（不依赖 hzfont 是否覆盖符号字符）
function M.icon(parent, cfg)
    local size = cfg.size or 18
    return airui.label({ parent = parent, symbol = cfg.symbol, x = cfg.x or 0, y = cfg.y or 0,
        w = cfg.w or (size + 6), h = cfg.h or (size + 6), font_size = size,
        color = cfg.color or C.text_dim })
end

-- ==================== 玻璃卡片 ====================
-- 返回 { root, card, sh, hl }；root 比 card 高 shadow_off+2，承载假投影
function M.glass_card(cfg)
    local off, w, h = G.shadow_off, cfg.w, cfg.h
    local root = airui.container({ parent = cfg.parent, x = cfg.x, y = cfg.y,
        w = w, h = h + off + 2, color = -1, border_width = 0, scrollable = false })
    -- 不画任何投影：LVGL 没有高斯模糊，任何实线（哪怕多档渐隐）在浅色主题下都会
    -- 被看成「多出来的横线」。层次完全交给 1px --hair 描边 + 卡片与背景的底色差。
    local rad = cfg.radius or T.r.card
    local sh
    local card = airui.container({ parent = root, x = 0, y = 0, w = w, h = h,
        color = C.card, radius = cfg.radius or T.r.card,
        border_width = 0, scrollable = false })
    M.glass(card, C.card, G.card_opa)
    reg("box", card, C.card, G.card_opa, "card_opa", "card")   -- 按令牌名取色，避免白色撞车
    -- 1px 描边：画在**外层容器**上（父容器比卡片大），描边落在卡片边缘、
    -- 不会被父容器裁掉半边；画在 card 自己身上会因“描边以路径为中心”而缺边。
    M.stroke(cfg.parent, cfg.x, cfg.y, w, h, cfg.radius or T.r.card, nil, nil, "hair_opa")
    -- 不再画「顶部高光条」：它就是一条 1px 亮线，深色主题下会被当成多出来的横线，
    -- 而 HTML 的 inset 高光在没有模糊/没有玻璃质感的情况下收益很小。
    return { root = root, card = card, sh = sh }
end

-- ==================== 热区 ====================
function M.press_layer(parent, cfg)
    local enabled = true
    local hit = airui.container({ parent = parent, x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h, color = 0xFFFFFF, color_opacity = 0,
        radius = cfg.radius or T.r.chip, border_width = 0, scrollable = false,
        on_click = function()
            if not enabled then return end
            -- 不再做「白色闪烁」：热区往往覆盖整张卡片，闪两次等于两次大面积 alpha 重绘，
            -- 在真机上就是点击后明显的迟滞感
            if cfg.on_click then cfg.on_click() end
        end })
    local handle = { obj = hit }
    function handle.set_enabled(a, b)
        local v = (b ~= nil) and b or a
        enabled = v and true or false
    end
    return handle
end

-- ==================== 档位 chip（附加服务 / 主题项） ====================
function M.chip(parent, cfg)
    local radius = cfg.radius or T.r.chip
    local box = M.box(parent, cfg.x, cfg.y, cfg.w, cfg.h,
        cfg.off_color or C.chip_off, radius, cfg.off_opa or 26)
    local ic = nil
    if cfg.icon_on then
        ic = M.icon(parent, { symbol = "", x = cfg.x + 8,
            y = cfg.y + math.floor((cfg.h - 20) / 2), size = 16, w = 18, h = 20,
            color = cfg.on_tcolor or C.on_pri })
    end
    local lbl = M.text_mid(parent, { text = cfg.text or "", x = cfg.x + (cfg.icon_on and 28 or 0),
        y = cfg.y, w = cfg.w - (cfg.icon_on and 32 or 0), h = cfg.h, size = cfg.size or T.f.sub,
        color = cfg.off_tcolor or C.chip_off_t,
        align = cfg.icon_on and airui.TEXT_ALIGN_LEFT or airui.TEXT_ALIGN_CENTER })
    local handle = { box = box, lbl = lbl, ic = ic, active = nil }
    function handle.set_active(v)
        v = v and true or false
        if v == handle.active then return end
        handle.active = v
        M.glass(box, v and (cfg.on_color or C.pri) or (cfg.off_color or C.chip_off),
            v and (cfg.on_opa or 255) or (cfg.off_opa or 26))
        pcall(function() lbl:set_color(v and (cfg.on_tcolor or C.on_pri) or (cfg.off_tcolor or C.chip_off_t)) end)
        if ic then pcall(function() ic:set_text(v and cfg.icon_on or "") end) end
    end
    if cfg.hit ~= false then
        M.press_layer(parent, { x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
            radius = radius, on_click = cfg.on_click })
    end
    handle.set_active(cfg.active)
    return handle
end

-- ==================== 进度条 ====================
function M.bar(parent, cfg)
    local obj = airui.bar({ parent = parent, x = cfg.x, y = cfg.y,
        w = cfg.w, h = cfg.h or 6, min = cfg.min or 0, max = cfg.max or 100,
        value = cfg.value or 0, radius = cfg.radius or 3,
        bg_color = cfg.bg_color or C.divider, indicator_color = cfg.color or C.pri,
        border_width = 0 })
    reg("bar", obj, cfg.color or C.pri)
    local handle = { obj = obj, last = -1, lastc = nil }
    function handle.set(v)
        if v < 0 then v = 0 elseif v > 100 then v = 100 end
        local n = math.floor(v + 0.5)
        if n == handle.last then return end          -- 值没变就不重绘
        handle.last = n
        pcall(function() obj:set_value(n, false) end)
    end
    function handle.color(c)
        if c == handle.lastc then return end
        handle.lastc = c
        pcall(function() obj:set_indicator_color(c) end)
    end
    return handle
end

-- ==================== 进度圆环（shape 的 arc 图元，带圆头，渲染平滑） ====================
function M.ring(parent, cfg)
    local r = cfg.r
    local w = cfg.width or 7
    local size = r * 2 + w + 6
    local c = math.floor(size / 2)
    local function items(p)
        p = math.max(0, math.min(1, p or 0))
        local prog = math.floor(360 * p + 0.5)
        local t = {
            -- 轨道：CSS --track 在晨曦白是「墨 .09」、夜青是「白 .11」，
            -- 固定用白色会在白卡片上完全隐形（只剩进度弧，看起来像缺了空心圆）
            { type = "arc", cx = c, cy = c, r = r, start_angle = 0, end_angle = 360,
              color = G.track_color or C.track_color or 0xFFFFFF, width = w,
              opacity = (G.ring_track_opa or 46) },
        }
        if prog > 0 then
            t[#t + 1] = { type = "arc", cx = c, cy = c, r = r, start_angle = -90,
                end_angle = -90 + prog, color = C.pri, width = w, rounded = true }
        end
        return t
    end
    local ok, obj = pcall(function()
        return airui.shape({ parent = parent, x = cfg.x, y = cfg.y, w = size, h = size, items = items(0) })
    end)
    if not (ok and obj) then return nil end
    local handle = { obj = obj, p = 0 }
    function handle.set(p)
        p = math.max(0, math.min(1, p))
        local lit = math.floor(p * 360 + 0.5)
        if lit == handle.p then return end
        handle.p = lit
        pcall(function() obj:set_items(items(p)) end)
    end
    -- 切主题时强制重画：轨道色是令牌色，而 set() 在进度没变时会跳过
    M.on_theme(function()
        if handle.obj then pcall(function() obj:set_items(items(handle.p / 360)) end) end
    end)
    return handle
end

-- 旧的分段折线环（保留备用，不再使用）
function M.ring_seg(parent, cfg)
    local segs = cfg.segs or 72
    local r = cfg.r
    local w, h = r * 2 + 8, r * 2 + 8
    local cx, cy = r + 4, r + 4
    local step = 2 * math.pi / segs
    local gap = 0.008
    local function items_at(lit)
        local items = {}
        for i = 1, segs do
            local a1 = -math.pi / 2 + (i - 1) * step + gap
            local a2 = -math.pi / 2 + i * step - gap
            local on = i <= lit
            items[#items + 1] = {
                type = "line",
                x1 = math.floor(cx + math.cos(a1) * r + 0.5),
                y1 = math.floor(cy + math.sin(a1) * r + 0.5),
                x2 = math.floor(cx + math.cos(a2) * r + 0.5),
                y2 = math.floor(cy + math.sin(a2) * r + 0.5),
                color = on and C.pri or C.soft,
                width = cfg.width or 7,
                opacity = on and 255 or (G.track_opa or 23),
            }
        end
        return items
    end
    -- 建对象时就带满一圈底环，避免空 items 的兼容问题
    local ok, o = pcall(function()
        return airui.shape({ parent = parent, x = cfg.x, y = cfg.y, w = w, h = h, items = items_at(0) })
    end)
    if not (ok and o) then return nil end
    local handle = { obj = o, p = 0 }
    function handle.set(p)
        p = math.max(0, math.min(1, p))
        local lit = math.floor(p * segs + 0.5)
        if lit == handle.p then return end
        handle.p = lit
        pcall(function() o:set_items(items_at(lit)) end)
    end
    return handle
end

-- ==================== 图片（找不到文件时返回 nil，调用方回退为色块） ====================
function M.photo(parent, cfg)
    if not cfg.src then return nil end          -- 无图片目录时直接走调用方的占位分支
    local ok, img = pcall(function()
        return airui.image({ parent = parent, x = cfg.x, y = cfg.y, w = cfg.w, h = cfg.h,
            src = cfg.src, fit = cfg.fit or "cover", opacity = cfg.opacity or 255 })
    end)
    if ok and img then return img end
    return nil
end

-- 颜色线性插值（用于近似 CSS 渐变 / 生成淡色）
function M.mix(a, b, t)
    local function ch(v, sh) return math.floor(v / sh) % 256 end
    local ar, ag, ab = ch(a, 65536), ch(a, 256), a % 256
    local br, bg, bb = ch(b, 65536), ch(b, 256), b % 256
    return math.floor(ar + (br - ar) * t + 0.5) * 65536
         + math.floor(ag + (bg - ag) * t + 0.5) * 256
         + math.floor(ab + (bb - ab) * t + 0.5)
end

return M
