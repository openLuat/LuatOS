--[[
@module  page_param
@summary UAV GCS - 飞控参数页（PID 列表 + 阶跃响应预测）
@version 1.0
@date    2026.11.02

左边是参数表，右边是**根据当前参数实时算出来的阶跃响应曲线**。
这不是装饰：真的把 P/I/D 拨一遍，曲线会立刻从"过阻尼爬得慢"变成"欠阻尼抖得厉害"，
超调量和上升时间也一起变。调参页面最怕的就是"拨完不知道后果"，这张图就是为了解决它。

响应模型（二阶欠阻尼，够用来判断趋势）：
  w = 2 + P*5 + I*3           自然频率：P/I 越大越快
  z = 0.25 + D*1.6            阻尼比：D 越大越不抖
  y(t) = 1 - e^(-z w t) [cos(wd t) + (z/sqrt(1-z²)) sin(wd t)]
超调量按 max(y)-1 取，上升时间取第一次到 0.9 的时刻。
]]
local fx = require "fx"
local T = require "theme"
local parts = require "parts"

local C = T.c
local M = {}

local L = T.param.list
local CH = T.param.chart
local IN = T.param.info
local TP_DOWN = T.TP_DOWN

local o = { root = nil, sel = 1, dirty = false }
local P = nil
local row = {}      -- 每行的 label 与命中区
local btn = {}      -- 底部按钮
local chart_shape, info_shape
local metric = {}

local PARAMS = {
    { key = "ROLL_P", name = "姿态环 P", val = 0.85, min = 0, max = 2.0, step = 0.05, def = 0.85 },
    { key = "ROLL_I", name = "姿态环 I", val = 0.35, min = 0, max = 1.5, step = 0.05, def = 0.35 },
    { key = "ROLL_D", name = "姿态环 D", val = 0.12, min = 0, max = 0.60, step = 0.01, def = 0.12 },
    { key = "SPD_P",  name = "速度环 P", val = 0.60, min = 0, max = 2.0, step = 0.05, def = 0.60 },
    { key = "SPD_I",  name = "速度环 I", val = 0.25, min = 0, max = 1.5, step = 0.05, def = 0.25 },
    { key = "ALT_P",  name = "高度环 P", val = 1.10, min = 0, max = 3.0, step = 0.10, def = 1.10 },
    { key = "YAW_P",  name = "偏航环 P", val = 0.70, min = 0, max = 2.5, step = 0.05, def = 0.70 },
    { key = "DFILT",  name = "D 项滤波", val = 0.30, min = 0, max = 1.0, step = 0.05, def = 0.30 },
}
M.PARAMS = PARAMS

-- 每行的横向分区（相对列表卡片左上角）
local X_NAME, X_VAL, X_BAR, X_MINUS, X_PLUS = 16, 190, 280, 512, 540
local W_BAR = 208

-- ==================== 阶跃响应 ====================
local SERIES = {}
for i = 1, 72 do SERIES[i] = 0 end

--[[按当前 PID 生成一条 0..1.5s 的阶跃响应
@return table 序列（下标 1..72）、超调量、上升时间
]]
local function make_response()
    local p = PARAMS[1].val
    local i_ = PARAMS[2].val
    local d = PARAMS[3].val
    local w = 2 + p * 5 + i_ * 3
    local z = fx.clamp(0.25 + d * 1.6, 0.05, 0.99)
    local wd = w * math.sqrt(1 - z * z)
    local n = #SERIES
    local over, rise = 0, 0
    for k = 1, n do
        local tt = (k - 1) / (n - 1) * 1.5
        local e = math.exp(-z * w * tt)
        local y = 1 - e * (math.cos(wd * tt) + (z / math.sqrt(1 - z * z)) * math.sin(wd * tt))
        SERIES[k] = y
        if y - 1 > over then over = y - 1 end
        if rise == 0 and y >= 0.9 then rise = tt end
    end
    if rise == 0 then rise = 1.5 end
    return SERIES, over, rise
end

-- ==================== 构建 ====================
function M.build(parent)
    o.root = parent
    P = fx.pool()

    -- ---------- 列表底 ----------
    local list_bg = parts.card(parent, L, "飞控参数 PARAMETERS", "PID", C.amber)
    local head = airui.shape({
        parent = parent, x = L.x, y = L.y, w = L.w, h = L.h, items = {},
    })
    P:reset()
    -- 表头分隔线
    P:line(16, 42, L.w - 17, 42, C.line2, 1, 220, false)
    P:line(X_BAR - 8, 42, X_BAR - 8, 436, C.line, 1, 100, false)
    P:finish()
    head:set_items(P.items)

    -- ---------- 参数行 ----------
    for i = 1, #PARAMS do
        local y = L.y + T.param.row_y + (i - 1) * T.param.row_h
        local sh = airui.shape({
            parent = parent, x = L.x, y = y, w = L.w, h = T.param.row_h - 2, items = {},
        })
        row[i] = {
            shape = sh,
            y = y,
            name = parts.lbl(parent, L.x + X_NAME, y + 6, 168, 20, PARAMS[i].name,
                T.f.body, C.txt, airui.TEXT_ALIGN_LEFT),
            key = parts.lbl(parent, L.x + X_NAME, y + 24, 168, 16, PARAMS[i].key,
                T.f.mini, C.dim2, airui.TEXT_ALIGN_LEFT),
            val = parts.lbl(parent, L.x + X_VAL, y + 11, 80, 24, "0.00",
                T.f.mid, C.amber, airui.TEXT_ALIGN_RIGHT),
        }
    end

    -- ---------- 底部按钮（落在列表卡片内，别探出边框）----------
    local bx = L.x + 16
    local by = L.y + 428
    local names = { "恢复默认", "写入飞控", "重新读取" }
    local cols = { C.dim, C.cyan, C.blue }
    for i = 1, 3 do
        local b = parts.button(parent, bx + (i - 1) * 152, by, 144, 38, names[i],
            cols[i], T.f.sub)
        parts.button_paint(b, false, cols[i])
        btn[i] = b
    end

    -- ---------- 曲线卡 ----------
    local chart_bg = parts.card(parent, CH, "阶跃响应 STEP", "1.5s", C.cyan)
    chart_shape = airui.shape({
        parent = parent, x = CH.x, y = CH.y, w = CH.w, h = CH.h, items = {},
    })
    metric.over = parts.lbl(parent, CH.x + 16, CH.y + 252, 150, 20, "超调 0.0 %",
        T.f.sub, C.amber, airui.TEXT_ALIGN_LEFT)
    metric.rise = parts.lbl(parent, CH.x + 176, CH.y + 252, 160, 20, "上升 0.00 s",
        T.f.sub, C.cyan, airui.TEXT_ALIGN_RIGHT)

    -- ---------- 说明卡 ----------
    local info_bg = parts.card(parent, IN, "参数说明 NOTE", "ROLL_P", C.violet)
    info_shape = airui.shape({
        parent = parent, x = IN.x, y = IN.y, w = IN.w, h = IN.h, items = {},
    })
    metric.title = parts.lbl(parent, IN.x + 16, IN.y + 40, IN.w - 32, 24, "姿态环 P",
        T.f.mid, C.txt, airui.TEXT_ALIGN_LEFT)
    metric.desc = parts.lbl(parent, IN.x + 16, IN.y + 74, IN.w - 32, 20, "",
        T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    metric.desc2 = parts.lbl(parent, IN.x + 16, IN.y + 96, IN.w - 32, 20, "",
        T.f.mini, C.dim, airui.TEXT_ALIGN_LEFT)
    metric.def = parts.lbl(parent, IN.x + 16, IN.y + 126, IN.w - 32, 20, "",
        T.f.sub, C.cyan, airui.TEXT_ALIGN_LEFT)
    metric.state = parts.lbl(parent, IN.x + 16, IN.y + 150, IN.w - 32, 20, "",
        T.f.sub, C.amber, airui.TEXT_ALIGN_LEFT)
end

-- ==================== 行重绘 ====================
local DESCS = {
    { "决定姿态偏差到角速度输出的力度", "太大：高频抖动 / 电机发热" },
    { "消除姿态的稳态偏差", "太大：低频摇摆 / 回中过冲" },
    { "抑制角速度突变，抗风的关键", "太大：响应变钝 / 引入噪声" },
    { "水平速度误差到倾角的转换系数", "太大：前后窜动" },
    { "消除速度稳态误差", "太大：刹车过冲" },
    { "高度误差到爬升率的转换系数", "太大：高度振荡" },
    { "航向误差到偏航角速度的系数", "太大：原地摆头" },
    { "D 项低通滤波，越小越平滑", "太小：电机发烫 / 手感发木" },
}

local function paint_rows()
    for i = 1, #PARAMS do
        local p = PARAMS[i]
        local r = row[i]
        local sel = (i == o.sel)
        P:reset()
        if sel then
            P:box(2, 0, L.w - 5, T.param.row_h - 4, C.amber, 20, 8)
            P:box(2, 8, 3, T.param.row_h - 20, C.amber, 230, 2)
        elseif i % 2 == 1 then
            P:box(2, 0, L.w - 5, T.param.row_h - 4, 0x0D1524, 120, 8)
        end
        -- 参数条：范围 + 当前值位置
        P:box(X_BAR, 18, W_BAR, 10, C.panel2, 220, 5)
        local t = (p.val - p.min) / (p.max - p.min)
        P:box(X_BAR, 18, W_BAR * t, 10, sel and C.amber or C.blue, 225, 5)
        P:dot(X_BAR + W_BAR * t, 23, 5, sel and C.amber or C.blue, 240)
        -- 默认值刻度
        local td = (p.def - p.min) / (p.max - p.min)
        P:line(X_BAR + W_BAR * td, 14, X_BAR + W_BAR * td, 32, C.dim, 1, 150, false)

        -- 减 / 加 按钮
        P:box(X_MINUS, 10, 22, 26, C.panel2, 235, 6)
        P:frame(X_MINUS, 10, 22, 26, C.line, 1, 230, 6)
        P:line(X_MINUS + 6, 23, X_MINUS + 16, 23, C.txt, 2, 220, true)
        P:box(X_PLUS, 10, 22, 26, C.panel2, 235, 6)
        P:frame(X_PLUS, 10, 22, 26, C.line, 1, 230, 6)
        P:line(X_PLUS + 6, 23, X_PLUS + 16, 23, C.txt, 2, 220, true)
        P:line(X_PLUS + 11, 18, X_PLUS + 11, 28, C.txt, 2, 220, true)

        P:finish()
        r.shape:set_items(P.items)

        parts.text(r.val, string.format("%.2f", p.val))
    end
end

-- ==================== 曲线 ====================
local function paint_chart()
    local series, over, rise = make_response()
    local n = #series
    -- 图元坐标是相对 chart_shape 左上角的，不是屏幕坐标
    local x0, y0, w, h = 16, 48, CH.w - 32, 190

    P:reset()
    P:box(x0, y0, w, h, 0x060B14, 235, 6)
    P:frame(x0, y0, w, h, C.line, 1, 200, 6)
    for i = 0, 4 do
        P:line(x0, y0 + i * h / 4, x0 + w, y0 + i * h / 4, C.line, 1, 80, false)
    end
    for i = 0, 6 do
        P:line(x0 + i * w / 6, y0, x0 + i * w / 6, y0 + h, C.line, 1, 60, false)
    end
    -- 目标线（1.0）：量程 0..1.6，所以 y = y0 + h*(1 - 1/1.6)
    local ty = y0 + h * (1 - 1 / 1.6)
    P:line(x0, ty, x0 + w, ty, C.dim, 1, 160, false)

    local xs, ys = P._sx, P._sy
    if not xs then
        xs, ys = {}, {}
        P._sx, P._sy = xs, ys
    end
    for k = 1, n do
        xs[k] = x0 + (k - 1) / (n - 1) * w
        local v = fx.clamp(series[k] / 1.6, 0, 1)
        ys[k] = y0 + h * (1 - v)
    end
    P:poly(xs, ys, n, C.cyan, 2, 240, true)
    P:dot(xs[n], ys[n], 3, C.cyan, 240)

    -- 超调峰值处点一颗琥珀色，一眼看到"抖了多少"
    if over > 0.005 then
        local peak, pk = -9, 1
        for k = 1, n do
            if series[k] > peak then peak = series[k]; pk = k end
        end
        P:line(xs[pk], ys[pk], xs[pk], ty, C.amber, 1, 120, false)
        P:dot(xs[pk], ys[pk], 3, C.amber, 240)
    end
    P:finish()
    chart_shape:set_items(P.items)

    parts.text(metric.over, string.format("超调 %.0f %%", over * 100))
    parts.text(metric.rise, string.format("上升 %.2f s", rise))
end

-- ==================== 说明卡 ====================
local function paint_info()
    local p = PARAMS[o.sel]
    local d = DESCS[o.sel]
    P:reset()
    -- 同样是相对 info_shape 的局部坐标
    P:line(16, 118, IN.w - 17, 118, C.line, 1, 180, false)
    P:box(16, 124, 3, 24, C.violet, 220, 2)
    P:finish()
    info_shape:set_items(P.items)

    parts.text(metric.title, p.name .. "  " .. p.key)
    parts.text(metric.desc, d[1])
    parts.text(metric.desc2, d[2])
    parts.text(metric.def, string.format("默认 %.2f    范围 %.2f ~ %.2f", p.def, p.min, p.max))
    parts.text(metric.state, o.dirty and "参数已修改，未写入飞控" or "参数与飞控一致")
end

-- ==================== 每帧 ====================
function M.draw(dt, t)
    paint_rows()
    paint_chart()
    paint_info()
end

-- ==================== 触摸 ====================
local function adjust(idx, dir)
    local p = PARAMS[idx]
    local v = p.val + dir * p.step
    p.val = fx.clamp(math.floor(v / p.step + 0.5) * p.step, p.min, p.max)
    o.sel = idx
    o.dirty = true
end

function M.on_touch(state, x, y)
    if state ~= TP_DOWN then return end

    -- 行
    for i = 1, #PARAMS do
        local ry = row[i].y
        if parts.hit(x, y, L.x, ry, L.w, T.param.row_h) then
            local lx = x - L.x
            if lx >= X_MINUS - 2 and lx <= X_MINUS + 24 then
                adjust(i, -1)
            elseif lx >= X_PLUS - 2 and lx <= X_PLUS + 24 then
                adjust(i, 1)
            else
                o.sel = i
            end
            return
        end
    end

    -- 底部按钮
    for i = 1, 3 do
        local b = btn[i]
        if parts.hit(x, y, b.x, b.y, b.w, b.h) then
            if i == 1 then
                for k = 1, #PARAMS do PARAMS[k].val = PARAMS[k].def end
                o.dirty = false
            elseif i == 2 then
                o.dirty = false
            else
                o.dirty = false
            end
            return
        end
    end
end

function M.leave() end

return M
