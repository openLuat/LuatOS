--[[
@module  kit
@summary 华康无菌车间 - 面板通用件（玻璃卡 / 标题 / 文本节流 / 折线 / 量条）
@version 1.0
@date    2026.11.11

=== 为什么单独抽一层 ===
七块面板共用同一套"卡片 + 标题 + 读数 + 量条 + 折线"的语法，抽出来以后
dashboard.lua 只关心"这块面板讲什么数据"，改视觉不用翻整份文件。

=== 两条纪律 ===
1、卡片(container) -> 图元(shape) -> 文字(label) 的创建顺序不能乱：
   LVGL 后建的子对象画在上层，图元画布必须压在文字之下。
2、M.put() 是文字写入的唯一入口：set_text 会让 LVGL 重新排版并多生成一块脏区，
   几十个 label 每帧 set_text 等于每秒上千次重排，帧率直接腰斩。
]]

local T = require "theme"
local fx = require "fx"

local M = {}

local c, f = T.c, T.f

-- ==================== 卡片 ====================
--[[
@param table parent 父容器
@param table r {x,y,w,h}
@param number accent 强调色（只用做标题左侧 3px 竖条，卡底不染色）
@return userdata container
]]
function M.card(parent, r, accent)
    local box = airui.container({
        parent = parent,
        x = r.x, y = r.y, w = r.w, h = r.h,
        color = c.panel, color_opacity = 255, radius = 8,
        border_color = c.line, border_width = 1,
    })
    if accent then
        -- 小 container 比图元便宜：静态、不进每帧图元预算
        airui.container({
            parent = box, x = 12, y = 13, w = 3, h = 14,
            color = accent, color_opacity = 255, radius = 1, border_width = 0,
        })
    end
    return box
end

-- 卡片标题（属于"文字阶段"，必须在 shape 之后调用）
function M.head(card, title, w, color)
    return airui.label({
        parent = card, x = 22, y = 10, w = (w or 150) - 26, h = 20,
        text = title, font_size = f.sub, color = color or c.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
end

-- 通用文字
function M.text(card, x, y, w, h, size, color, align, txt)
    return airui.label({
        parent = card, x = x, y = y, w = w, h = h,
        text = txt or "", font_size = size or f.body, color = color or c.txt,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 右上角小标签
function M.tag(card, x, y, w, txt, color, size)
    return airui.label({
        parent = card, x = x, y = y, w = w, h = 18,
        text = txt or "", font_size = size or f.mini, color = color or c.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
    })
end

-- ==================== 文字节流 ====================
--[[
@param userdata lb label 对象
@param string txt 新文本
@param table o 界面对象（缓存挂在 o._tx 上）
@param string key 文本槽名
内容与上次相同时直接返回，不触发 LVGL 重排。
]]
function M.put(lb, txt, o, key)
    if not lb then return end
    local cache = o._tx
    if not cache then
        cache = {}
        o._tx = cache
    end
    if cache[key] == txt then return end
    cache[key] = txt
    lb:set_text(txt)
end

-- 颜色也做缓存：set_color 同样会触发重绘
function M.tint(lb, col, o, key)
    if not lb then return end
    local cache = o._txc
    if not cache then
        cache = {}
        o._txc = cache
    end
    key = key or "?"
    if cache[key] == col then return end
    cache[key] = col
    lb:set_color(col)
end

-- 累积出"热帧"（默认 4Hz）
function M.hot(o, dt, ms)
    o.textT = (o.textT or 0) + dt * 1000
    local period = ms or T.perf.text_ms
    if o.textT >= period then
        o.textT = 0
        o.hot = true
    else
        o.hot = false
    end
    return o.hot
end

-- ==================== 图元 ====================
-- 四角记号：只画左上 / 右下两个 L 形角标，用来标"这个房间此刻被选中"
function M.brackets(P, x, y, w, h, color, opa, len)
    len = len or 8
    opa = opa or 150
    local x1, y1 = x + w - 1, y + h - 1
    P:line(x, y, x + len, y, color, 2, opa)
    P:line(x, y, x, y + len, color, 2, opa)
    P:line(x1, y1, x1 - len, y1, color, 2, opa)
    P:line(x1, y1, x1, y1 - len, color, 2, opa)
end

-- 细分隔线
function M.divider(P, x, y, w, color, opa)
    P:line(x, y, x + w, y, color or c.line, 1, opa or 90)
end

--[[折线：把数值序列铺到矩形里
@param table vals 值数组
@param int n 点数
@param number vmin 量程下限（不是 0 时曲线才不会全挤在顶上）
@param number vmax 量程上限
]]
function M.line(P, vals, n, x, y, w, h, vmin, vmax, color, width, opa)
    if n < 2 then return end
    local xs, ys = P._sx, P._sy
    if not xs then
        xs, ys = {}, {}
        P._sx, P._sy = xs, ys
    end
    local step = w / (n - 1)
    local span = vmax - vmin
    if span <= 0 then span = 1 end
    for i = 1, n do
        local v = ((vals[i] or vmin) - vmin) / span
        if v < 0 then v = 0 elseif v > 1 then v = 1 end
        xs[i] = x + (i - 1) * step
        ys[i] = y + h - v * h
    end
    P:poly(xs, ys, n, color, width or 2, opa or 220, true)
    return xs, ys
end

-- 量条：面板层统一从 kit 取件，不必同时 require fx
M.meter = fx.meter
M.vmeter = fx.vmeter

--[[压差色阶（对走廊压差，单位 Pa）
药典要求洁净区对相邻低级别区 >= 10Pa。所以：
  < 8    红（失守，必须马上查送风）
  8..10  琥珀（踩着下限跑，门一开就掉下去）
  10..18 冰蓝（正常）
  > 18   亮青（送风偏大，能耗偏高，但不影响合规）
]]
function M.dp_color(v)
    if v < 8 then return c.alarm end
    if v < 10 then return c.amber end
    if v <= 18 then return c.ice end
    return c.cyan
end

-- 温湿度色阶：只看是否在 18~26C / 45~60%RH 的框里
function M.th_color(v, lo, hi, soft)
    if v < lo - soft or v > hi + soft then return c.alarm end
    if v < lo or v > hi then return c.amber end
    return c.mint
end

-- 粒子色阶：frac 是当前值 / 该级别限值
function M.part_color(frac)
    if frac >= 1.0 then return c.alarm end
    if frac >= 0.75 then return c.amber end
    return c.mint
end

return M
