--[[
@module  parts
@summary UAV GCS - 通用控件积木（标签 / 卡片 / 条形 / 火花线 / 按钮）
@version 1.0
@date    2026.11.02

=== 为什么卡片底板用 shape 而不是 container ===
container 就是 lv_obj_create，默认带 LV_OBJ_FLAG_SCROLLABLE：
只要子对象包围盒比内容区大一点点（描边 1px、字体行高比给的高 1px、以后多加一个字），
LVGL 就判定"可滚动"，在右/下画出滚动条 —— 真机上就是"卡片里多一圈方角细框"。
shape 在 C 层硬编码了 remove_flag(SCROLLABLE)，永远不可能画出滚动条，
而且一块底板只要 4 个图元（填充 + 描边 + 顶部高光 + 左侧色块），比 container 还便宜。
所以：卡片 = shape 底板 + 直接挂在 shape 上的 label。

=== 文字缓存 ===
LVGL 每次 set_text 都要重新排版，30fps 全量写回是纯浪费。
parts.text 用组件对象本身当键（userdata 可以做表键），只在值真的变了才写。
]]
local fx = require "fx"
local T = require "theme"

local C = T.c
local floor = math.floor
local clamp = fx.clamp
local shade = fx.shade

local M = {}

M.f = T.f
M.c = C

-- ==================== 标签 ====================
function M.lbl(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent,
        x = floor(x), y = floor(y), w = floor(w), h = floor(h),
        text = text or "",
        font_size = size,
        color = color or C.txt,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

local cache = setmetatable({}, { __mode = "k" })

-- 只在文本真的变化时写回
function M.text(node, s)
    if not node or s == nil then return end
    s = tostring(s)
    if cache[node] ~= s then
        cache[node] = s
        node:set_text(s)
    end
end

function M.color(node, col)
    if not node then return end
    node:set_color(col)
end

-- ==================== 卡片底板 ====================
local card_pool = nil
local function shared_pool()
    if not card_pool then card_pool = fx.pool() end
    return card_pool
end

--[[C 层画矩形用的是 x2 = x + w（含端点），所以宽高各减 1 才是"正好铺满"，
否则右下各多 1px 会被图层裁掉，描边看起来缺一条边。]]
function M.panel_bg(P, w, h, tint)
    P:box(0, 0, w - 1, h - 1, C.panel, 250, 14)
    P:frame(0, 0, w - 1, h - 1, C.line, 1, 255, 14)
    P:line(18, 1, w - 19, 1, tint or C.cyan, 1, 120, true)
    P:box(0, 12, 3, 22, tint or C.cyan, 210, 2)
end

--[[创建一张卡片：底板 + 左上标题 + 右上英文/单位
@return userdata shape 卡片底板（label 直接挂它上面）
]]
function M.card(parent, geo, title, en, tint)
    local s = airui.shape({
        parent = parent, x = geo.x, y = geo.y, w = geo.w, h = geo.h, items = {},
    })
    if not s then
        log.error("uav", "卡片 shape 创建失败", geo.x, geo.y)
        return nil
    end
    local P = shared_pool()
    P:reset()
    M.panel_bg(P, geo.w, geo.h, tint)
    P:finish()
    s:set_items(P.items)

    -- 标题区与右上角标各区 140/108 像素：label 不会自动裁字，
    -- 两块挨太近时长标题会顶到角标上
    if title then
        M.lbl(s, 16, 8, geo.w - 140, 20, title, T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    end
    if en then
        M.lbl(s, geo.w - 124, 8, 108, 20, en, T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT)
    end
    return s
end

-- ==================== 条形 ====================
--[[水平能量条：暗轨道 + 发光填充 + 前沿光点]]
function M.meter(P, x, y, w, h, frac, color)
    frac = clamp(frac, 0, 1)
    P:box(x, y, w, h, C.panel2, 220, floor(h / 2))
    local fw = w * frac
    if fw >= 2 then
        P:box(x, y, fw, h, color, 235, floor(h / 2))
        P:dot(x + fw, y + h / 2, floor(h * 0.8), color, 55)
        P:dot(x + fw, y + h / 2, floor(h * 0.36), shade(color, 0.55), 210)
    end
end

--[[垂直条：底在 (x, y+h)，向上填充 frac]]
function M.vbar(P, x, y, w, h, frac, color, opa)
    frac = clamp(frac, 0, 1)
    P:box(x, y, w, h, C.panel2, 220, 3)
    local fh = h * frac
    if fh >= 2 then
        P:box(x, y + h - fh, w, fh, color, opa or 235, 3)
        P:line(x + 1, y + h - fh, x + w - 1, y + h - fh, shade(color, 0.6), 2, 240, true)
    end
end

-- ==================== 火花线 ====================
--[[把一维序列画成折线
@param table P 图元池
@param table vals 值数组（下标 1..n）
@param number n 有效点数
@param number vmin,vmax 值域（用来把值映射到高度）
]]
function M.spark(P, vals, n, x, y, w, h, vmin, vmax, color, width, opa, fill)
    if n < 2 then return end
    local xs, ys = P._sx, P._sy
    if not xs then
        xs, ys = {}, {}
        P._sx, P._sy = xs, ys
    end
    local span = vmax - vmin
    if span <= 0 then span = 1 end
    local step = w / (n - 1)
    local base = y + h
    for i = 1, n do
        xs[i] = x + (i - 1) * step
        local t = (vals[i] - vmin) / span
        ys[i] = base - clamp(t, 0, 1) * h
    end
    if fill then
        -- 面积：逐列画一根到底的细竖线，比多边形填充省事且不会漏
        local bw = math.max(1, floor(step))
        for i = 1, n - 1 do
            P:line(xs[i], ys[i], xs[i], base, color, bw, 26, false)
        end
    end
    P:poly(xs, ys, n, color, width or 2, opa or 220, true)
end

-- ==================== 按钮 ====================
--[[动作按钮：圆角底板 + 居中文字，返回 {shape=, label=, x, y, w, h}
点击热区由页面自己判定（on_touch），不依赖 LVGL 的 on_click。
]]
function M.button(parent, x, y, w, h, text, accent, size)
    local s = airui.shape({
        parent = parent, x = x, y = y, w = w, h = h, items = {},
    })
    if not s then
        log.error("uav", "按钮 shape 创建失败", x, y)
        return { x = x, y = y, w = w, h = h }
    end
    local fs = size or T.f.body
    local lb = M.lbl(s, 0, floor((h - fs) / 2) - 2, w, fs + 8,
        text, fs, C.txt, airui.TEXT_ALIGN_CENTER)
    return { shape = s, label = lb, x = x, y = y, w = w, h = h }
end

-- 按钮两种状态的底板（选中/未选中）
function M.button_paint(btn, on, accent)
    if not btn or not btn.shape then return end
    local P = shared_pool()
    P:reset()
    local w, h = btn.w, btn.h
    local ac = accent or C.cyan
    if on then
        P:box(0, 0, w - 1, h - 1, ac, 34, 12)
        P:frame(0, 0, w - 1, h - 1, ac, 2, 230, 12)
        P:line(14, 1, w - 15, 1, ac, 1, 200, true)
    else
        P:box(0, 0, w - 1, h - 1, C.panel2, 235, 12)
        P:frame(0, 0, w - 1, h - 1, C.line, 1, 240, 12)
    end
    P:finish()
    btn.shape:set_items(P.items)
end

-- ==================== 背景网格 ====================
-- 点阵网格：比密集线网格省一半图元，远看是"舱内屏幕"的质感
function M.dots(P, x, y, w, h, step, color, opa)
    local yy = y
    while yy < y + h do
        local xx = x
        while xx < x + w do
            P:dot(xx, yy, 1, color, opa)
            xx = xx + step
        end
        yy = yy + step
    end
end

-- ==================== 小工具 ====================
function M.hit(x, y, rx, ry, rw, rh)
    return x >= rx and x <= rx + rw and y >= ry and y <= ry + rh
end

--[[按字符（不是字节）截断，超长补 ".."
label 不裁剪文本，超长会顶出卡片边界，所以日志这类外部文本一律先截。
中文一个字 3 字节，按字节切会切出半个汉字变成方框。]]
function M.cut(s, n)
    if not s then return "" end
    if not utf8 or not utf8.len then return s end
    local ok, len = pcall(utf8.len, s)
    if not ok or not len or len <= n then return s end
    local i = utf8.offset(s, n + 1)
    if not i then return s end
    return string.sub(s, 1, i - 1) .. ".."
end

return M
