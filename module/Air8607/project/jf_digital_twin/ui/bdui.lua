--[[
@module  bdui
@summary DIGITAL TWIN - 面板通用件（玻璃卡 / 标题 / 数值节流 / 角标 / 进度条 / 弧）
@version 1.0
@date    2026.10.23
@author  江访

=== 为什么单独抽一层 ===
三个视图共用同一套"玻璃面板"的语法：卡片底、标题、读数、角标、进度条、弧。
抽出来以后，视图文件只剩下"这块面板讲什么数据"，改视觉不用动三份。

=== 两条纪律 ===
1、`M.card()` 只建**容器**，不建 label。
   LVGL 后建的子对象画在上层，视图里的 shape 画布要压在所有 label 之下，
   所以调用顺序必须是：卡片容器 -> 图片 -> shape -> 文字。
2、`M.put()` 是文字节流的唯一入口：
   set_text 会让 LVGL 重排文本并多出一块脏区，140 个 label 每帧 set_text
   等于每秒四千次重排，帧率直接腰斩。
]]

local T = require "theme"

local M = {}

local c = T.c
local f = T.f

-- ==================== 玻璃卡片 ====================
--[[
@param table parent 父容器
@param table r {x,y,w,h} 视图局部坐标
@param number accent 强调色（只用来做标题左侧的 3px 竖条，卡片底不染色）
@return userdata container
]]
function M.card(parent, r, accent)
    local box = airui.container({
        parent = parent,
        x = r.x, y = r.y, w = r.w, h = r.h,
        color = c.panel, color_opacity = 216, radius = 8,
        border_color = c.line, border_width = 1,
    })
    if accent then
        -- 标题左侧的强调竖条：一个小 container 比图元便宜（静态，不进图元预算）
        airui.container({
            parent = box, x = 12, y = 13, w = 3, h = 12,
            color = accent, color_opacity = 255, radius = 1, border_width = 0,
        })
    end
    return box
end

-- 标题（属于"文字阶段"，必须在 shape 之后调用）
function M.head(card, title, w, color)
    return airui.label({
        parent = card, x = 22, y = 9, w = (w or 150) - 26, h = 20,
        text = title, font_size = f.sub, color = color or c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
end

-- 卡片右上角的"标签"（如单位、状态）
function M.tag(card, x, y, w, text_, color, size)
    return airui.label({
        parent = card, x = x, y = y, w = w, h = 18,
        text = text_ or "", font_size = size or f.mini, color = color or c.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- 通用文字
function M.text(card, x, y, w, h, size, color, align, txt)
    return airui.label({
        parent = card, x = x, y = y, w = w, h = h,
        text = txt or "", font_size = size or f.text, color = color or c.txt,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

-- ==================== 文字节流 ====================
--[[
@param userdata lb label 对象
@param string txt 新文本
@param table o 视图对象（缓存挂在 o._tx 上）
@param string key 文本槽名
视图 update 开头调用 M.hot(o, dt) 维护 o.hot，只有 hot 帧才真的 set_text。
]]
function M.put(lb, txt, o, key)
    if not lb then return end
    local cache = o._tx
    if not cache then
        cache = {}
        o._tx = cache
    end
    if not o.hot or cache[key] == txt then return end
    cache[key] = txt
    lb:set_text(txt)
end

-- 累积出 5Hz 的"热帧"
function M.hot(o, dt)
    o.textT = (o.textT or 0) + dt
    if o.textT >= T.perf.text_ms / 1000 then
        o.textT = 0
        o.hot = true
    else
        o.hot = false
    end
    return o.hot
end

-- ==================== 图元：装饰 ====================
--[[四角记号：只画左上 / 右下两个 L 形角标（4 条线），比整圈描边省 4 个图元
@param table P 图元池
@param table r {x,y,w,h}
]]
function M.brackets(P, r, color, opa, len)
    len = len or 10
    opa = opa or 150
    local x0, y0 = r.x, r.y
    local x1, y1 = r.x + r.w - 1, r.y + r.h - 1
    P:line(x0, y0, x0 + len, y0, color, 1, opa)
    P:line(x0, y0, x0, y0 + len, color, 1, opa)
    P:line(x1, y1, x1 - len, y1, color, 1, opa)
    P:line(x1, y1, x1, y1 - len, color, 1, opa)
end

-- 四角取景框（8 条线）：给中央"场景视口"用，把实景和叠加层框成一块
function M.brackets4(P, r, color, opa, len)
    len = len or 16
    opa = opa or 100
    local x0, y0 = r.x, r.y
    local x1, y1 = r.x + r.w - 1, r.y + r.h - 1
    P:line(x0, y0, x0 + len, y0, color, 1, opa)
    P:line(x0, y0, x0, y0 + len, color, 1, opa)
    P:line(x1, y0, x1 - len, y0, color, 1, opa)
    P:line(x1, y0, x1, y0 + len, color, 1, opa)
    P:line(x0, y1, x0 + len, y1, color, 1, opa)
    P:line(x0, y1, x0, y1 - len, color, 1, opa)
    P:line(x1, y1, x1 - len, y1, color, 1, opa)
    P:line(x1, y1, x1, y1 - len, color, 1, opa)
end

-- 细分隔线
function M.divider(P, x, y, w, color, opa)
    P:line(x, y, x + w, y, color or c.line2, 1, opa or 90)
end

--[[水平进度条：暗轨 + 填充 + 端点光晕（4 个图元）
@param number frac 0..1
]]
function M.bar(P, x, y, w, h, frac, color, track)
    P:box(x, y, w, h, track or 0x0F2236, 220, math.floor(h / 2))
    frac = frac < 0 and 0 or (frac > 1 and 1 or frac)
    local fw = math.floor(w * frac)
    if fw >= 2 then
        P:box(x, y, fw, h, color, 235, math.floor(h / 2))
        P:dot(x + fw, y + h / 2, math.floor(h * 0.85), color, 55)
        P:dot(x + fw, y + h / 2, math.max(1, math.floor(h * 0.34)), color, 210)
    end
end

--[[进度弧：整圈暗轨 + 若干点串进度（点半径沿弧长递增，自带辉光）
@param number a0,a1 起止弧度（屏幕角度：0 在 3 点方向，顺时针为正、y 轴向下）
@param number dots 点串颗数
]]
function M.gauge(P, cx, cy, r, frac, color, a0, a1, width, dots)
    P:ring(cx, cy, r, 0x123049, width or 6, 200)
    frac = frac < 0 and 0 or (frac > 1 and 1 or frac)
    dots = dots or 14
    local span = (a1 - a0) * frac
    for i = 1, dots do
        local t = i / dots
        local a = a0 + span * t
        local rr = r + (width or 6) * 0.1
        P:dot(cx + math.cos(a) * rr, cy + math.sin(a) * rr,
            math.floor((width or 6) * (0.32 + 0.22 * t) + 0.5),
            color, math.floor(90 + 165 * t))
    end
    -- 头点：弧末端一颗亮白点，读数变化时肉眼能追上
    local ae = a0 + span
    P:dot(cx + math.cos(ae) * r, cy + math.sin(ae) * r, 3, 0xFFFFFF, 230)
end

-- 折线趋势（0..1 序列）
function M.spark(P, vals, n, x, y, w, h, color, width, opa)
    if n < 2 then return end
    local xs, ys = P._sx, P._sy
    if not xs then
        xs, ys = {}, {}
        P._sx, P._sy = xs, ys
    end
    local step = w / (n - 1)
    for i = 1, n do
        local v = vals[i] or 0
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        xs[i] = x + (i - 1) * step
        ys[i] = y + h - v * h
    end
    P:poly(xs, ys, n, color, width or 1, opa or 200, false)

    -- 末端光点
    local lx, ly = xs[n], ys[n]
    P:dot(lx, ly, 2, color, 235)
    P:dot(lx, ly, 6, color, 60)
end

-- ==================== 状态配色 ====================
M.STATE_COL = { c.teal, c.cyan, c.amber, c.red }
M.STATE_TXT = { "运行", "待机", "告警", "停机" }
M.LEVEL_COL = { c.cyan, c.amber, c.red }

return M
