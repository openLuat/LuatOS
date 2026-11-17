--[[
@module  art
@summary IMM-6 图元库：注塑机剖面、成型周期环、工艺曲线、温度柱、图标
@version 1.0
@date    2026.11.15

全部用 airui.shape 的四类图元（line / circle / ellipse / rect / arc）拼绘，不依赖图片资源。
降载约定：
  1、静态结构只建一次；
  2、随工艺变化的部分单独一个 shape，按量化档位重建；
  3、逐帧动画只对 container 做 set_pos，不碰图元数组。
]]
local theme = require "theme"
local C = theme.C

local M = {}

local function I(v) return math.floor(v + 0.5) end

local function clamp01(t)
    if t < 0 then return 0 elseif t > 1 then return 1 end
    return t
end
M.clamp01 = clamp01

-- ===================== 图元构造 =====================
local function circle(items, cx, cy, r, color, fill, opa, width, fill_opa)
    items[#items + 1] = {
        type = "circle", cx = I(cx), cy = I(cy), r = math.max(1, I(r)),
        color = color, width = width or 1, opacity = opa or 255,
        fill = fill and true or false,
        fill_color = color, fill_opacity = (fill and (fill_opa or 255) or 0),
    }
end

local function ring(items, cx, cy, r, color, width, opa)
    items[#items + 1] = {
        type = "circle", cx = I(cx), cy = I(cy), r = math.max(1, I(r)),
        color = color, width = width or 1, opacity = opa or 255, fill = false,
    }
end

local function line(items, x1, y1, x2, y2, color, width, opa, dash, gap)
    items[#items + 1] = {
        type = "line", x1 = I(x1), y1 = I(y1), x2 = I(x2), y2 = I(y2),
        color = color, width = width or 2, opacity = opa or 255,
        round_start = true, round_end = true,
        dash_width = dash or 0, dash_gap = gap or 0,
    }
end

local function arc(items, cx, cy, r, a1, a2, color, width, opa)
    items[#items + 1] = {
        type = "arc", cx = I(cx), cy = I(cy), r = math.max(1, I(r)),
        start_angle = a1, end_angle = a2, color = color,
        width = width or 2, opacity = opa or 255, rounded = true,
    }
end

local function rect(items, x, y, w, h, color, radius, fill, opa)
    items[#items + 1] = {
        type = "rect", x = I(x), y = I(y), w = math.max(1, I(w)), h = math.max(1, I(h)),
        radius = I(radius or 0), color = color, width = 1, opacity = opa or 255,
        fill = fill and true or false, fill_color = color,
        fill_opacity = (fill and (opa or 255) or 0),
    }
end

local function ellipse(items, cx, cy, rx, ry, color, width, opa, fill, fill_opa)
    items[#items + 1] = {
        type = "ellipse", cx = I(cx), cy = I(cy), rx = math.max(1, I(rx)), ry = math.max(1, I(ry)),
        color = color, width = width or 1, opacity = opa or 255,
        fill = fill and true or false, fill_color = color, fill_opacity = (fill and (fill_opa or 255) or 0),
    }
end

local function polyline(items, pts, color, width, opa, dash, gap)
    for i = 2, #pts do
        line(items, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], color, width, opa, dash, gap)
    end
end
M.polyline = polyline

-- ===================== 注塑机剖面 =====================
--[[
左半为锁模单元（后模板 / 机铰 / 移动模板 / 动模 / 定模 / 固定模板 / 四根拉杆），
右半为注射单元（料筒 / 螺杆 / 料斗 / 五段加热圈 / 喷嘴）。

几何常量集中在 G 里，页面只关心 set_mold / set_screw / set_heat / set_part 四个动作。
opts: { mx0=130, mx1=206 }  移动模板的开启位与闭合位
]]
function M.imm(parent, w, h, opts)
    opts = opts or {}
    local G = {
        base_y = h - 44,
        top_y = 44,
        mx0 = opts.mx0 or 126,     -- 开模时移动模板左缘
        mx1 = opts.mx1 or 204,     -- 合模时移动模板左缘
        mold_gap = 74,             -- 开模最大间隙
        barrel_x = 330,
        barrel_w = 230,
        barrel_y = h * 0.46,
        barrel_h = 32,
    }
    G.mx1 = G.mx0 + G.mold_gap

    local PL_W = 22        -- 移动模板厚
    local MOLD_W = 28
    local FIX_X = G.mx1 + PL_W + MOLD_W   -- 定模左缘
    local FIX_PL = FIX_X + MOLD_W          -- 固定模板左缘

    local items = {}

    -- 底座
    rect(items, 6, G.base_y, w - 12, 18, 0x1B2029, 2, true, 255)
    rect(items, 6, G.base_y, w - 12, 1, C.steel, 0, true, 150)
    for i = 0, 8 do
        local x = 16 + i * (w - 32) / 8
        line(items, x, G.base_y + 4, x, G.base_y + 14, C.steel, 1, 90)
    end

    -- 拉杆（上下两根横贯锁模区）
    line(items, FIX_PL + 8, G.top_y + 18, 34, G.top_y + 18, C.steel, 5, 255)
    line(items, FIX_PL + 8, G.base_y - 16, 34, G.base_y - 16, C.steel, 5, 255)
    line(items, FIX_PL + 8, G.top_y + 18, 34, G.top_y + 18, C.steel2, 1, 120)

    -- 后模板（固定）
    rect(items, 22, G.top_y + 4, 20, G.base_y - G.top_y - 4, 0x222834, 2, true, 255)
    rect(items, 22, G.top_y + 4, 20, G.base_y - G.top_y - 4, C.steel, 2, false, 220)

    -- 机铰：后模板到移动模板的两条斜撑
    local mid_y = (G.top_y + G.base_y) / 2
    line(items, 42, G.top_y + 20, G.mx0 - 4, mid_y - 10, C.steel, 4, 230)
    line(items, 42, G.base_y - 18, G.mx0 - 4, mid_y + 10, C.steel, 4, 230)

    -- 固定模板 + 定模
    rect(items, FIX_PL, G.top_y - 2, 22, G.base_y - G.top_y + 2, 0x222834, 2, true, 255)
    rect(items, FIX_PL, G.top_y - 2, 22, G.base_y - G.top_y + 2, C.steel, 2, false, 230)
    local mold_y = mid_y - 42
    local mold_h = 84
    rect(items, FIX_X, mold_y, MOLD_W, mold_h, 0x2B3240, 2, true, 255)
    rect(items, FIX_X, mold_y, MOLD_W, mold_h, C.steel2, 2, false, 200)
    -- 型腔（定模侧）
    rect(items, FIX_X + 8, mold_y + 16, 12, mold_h - 32, 0x141922, 2, true, 255)

    -- 注射单元：喷嘴 / 料筒 / 螺杆套筒
    local bx, by, bw, bh = G.barrel_x, G.barrel_y, G.barrel_w, G.barrel_h
    -- 喷嘴
    rect(items, FIX_PL + 22, mid_y - 7, bx - FIX_PL - 22, 14, 0x3A4250, 2, true, 255)
    rect(items, bx - 12, mid_y - 9, 12, 18, C.steel2, 2, true, 240)
    -- 料筒本体
    rect(items, bx, by, bw, bh, 0x303845, 3, true, 255)
    rect(items, bx, by, bw, bh, C.steel2, 3, false, 220)
    -- 料筒内的衬套
    rect(items, bx + 4, by + 9, bw - 8, bh - 18, 0x1A1F28, 2, true, 255)
    -- 料斗
    local hx, hy = bx + bw * 0.42, by - 60
    local hopper = {
        { hx, hy }, { hx + 40, hy }, { hx + 30, by - 4 }, { hx + 8, by - 4 },
    }
    polyline(items, { { hx, hy }, { hx + 40, hy }, { hx + 30, by - 4 }, { hx + 8, by - 4 }, { hx, hy } },
        C.steel2, 2, 230)
    rect(items, hx + 2, hy + 2, 36, 4, C.steel, 1, true, 200)
    -- 粒料
    for i = 0, 5 do
        local px = hx + 8 + (i % 4) * 7
        local py = hy + 12 + math.floor(i / 4) * 8
        circle(items, px, py, 2, theme.mix(C.ink3, C.amber, 0.35), true, 200, 1, 200)
    end
    -- 干燥热风管
    line(items, hx + 20, hy - 2, hx + 20, hy - 22, C.steel, 3, 230)
    line(items, hx + 20, hy - 22, hx + 54, hy - 22, C.steel, 3, 230)
    line(items, hx + 54, hy - 22, hx + 54, hy - 6, C.steel, 3, 230)


    local static_shape = theme.shape(parent, 0, 0, w, h, items)

    -- ===== 移动模板组（容器移动，子对象跟随）=====
    -- 容器必须比子对象大：LVGL 的 container 会裁剪超出边界的子对象
    local OX = 12
    local plate = theme.box(parent, G.mx0 - OX, G.top_y, PL_W + MOLD_W + OX + 10,
        G.base_y - G.top_y + 6, 0x000000, 0, 0)
    local plate_items = {}
    rect(plate_items, OX, 4, PL_W, G.base_y - G.top_y - 4, 0x252C38, 2, true, 255)
    rect(plate_items, OX, 4, PL_W, G.base_y - G.top_y - 4, C.steel2, 2, false, 230)
    -- 动模
    rect(plate_items, OX + PL_W, mold_y - G.top_y, MOLD_W, mold_h, 0x2B3240, 2, true, 255)
    rect(plate_items, OX + PL_W, mold_y - G.top_y, MOLD_W, mold_h, C.steel2, 2, false, 200)
    rect(plate_items, OX + PL_W + 8, mold_y - G.top_y + 16, 12, mold_h - 32, 0x141922, 2, true, 255)
    -- 顶针板
    rect(plate_items, OX - 8, mold_y - G.top_y + 26, 8, 32, 0x3A4250, 1, true, 240)
    -- 哥林柱导套
    circle(plate_items, OX + PL_W / 2, 18, 5, C.steel2, false, 220, 2)
    circle(plate_items, OX + PL_W / 2, G.base_y - G.top_y - 34, 5, C.steel2, false, 220, 2)
    local plate_shape = theme.shape(plate, 0, 0, PL_W + MOLD_W + OX + 10, G.base_y - G.top_y + 6, plate_items)

    -- ===== 螺杆组 =====
    local screw = theme.box(parent, bx, by, bw, bh, 0x000000, 0, 0)
    local screw_items = {}
    local s_len = bw - 16
    rect(screw_items, 0, bh / 2 - 4, s_len, 8, 0x6B7688, 3, true, 255)
    for i = 0, 13 do
        local x = 8 + i * (s_len - 16) / 13
        line(screw_items, x, bh / 2 - 8, x + 5, bh / 2 + 8, C.ink3, 1, 170)
    end
    -- 止逆环
    rect(screw_items, 2, bh / 2 - 9, 6, 18, C.amber, 1, true, 220)
    local screw_shape = theme.shape(screw, 0, 0, bw, bh, screw_items)

    -- ===== 熔料（随螺杆位置变化）=====
    local melt_shape = theme.shape(parent, 0, 0, w, h, {})

    -- ===== 加热圈（五段，随温度变色）=====
    local heat_shape = theme.shape(parent, 0, 0, w, h, {})

    -- ===== 取件（顶出后落下的小方料）=====
    local part = theme.box(parent, FIX_X + 6, mid_y, 16, 12, C.melt, 2, 0)
    local part_shape = theme.shape(part, 0, 0, 16, 12, {
        { type = "rect", x = 0, y = 0, w = 15, h = 11, radius = 2, color = C.melt,
          width = 1, opacity = 255, fill = true, fill_color = C.melt, fill_opacity = 235 },
    })
    pcall(function() part:set_hidden(true) end)

    local obj = { geo = G, mid_y = mid_y, mold_y = mold_y, mold_h = mold_h,
                  barrel = { x = bx, y = by, w = bw, h = bh }, state = {} }

    -- 合模进度 0..1：移动模板从开启位滑到闭合位
    -- 量化到 1/50，既避免重复 set_pos，又能在 9 fps 下看出连续滑动
    function obj.set_mold(pct)
        pct = clamp01(pct or 0)
        local q = math.floor(pct * 50 + 0.5) / 50
        if obj.state.mold == q then return end
        obj.state.mold = q
        local x = G.mx0 + (G.mx1 - G.mx0) * q
        pcall(function() plate:set_pos(I(x - OX), I(G.top_y)) end)
    end
    obj.set_mold(0)

    -- 螺杆位置 0..1：1 为后退到底（已熔胶），0 为注射到底
    -- 位移每帧更新；熔料色块只在跨 1/10 档时重建，避免 9 fps 反复分配图元
    function obj.set_screw(pct)
        pct = clamp01(pct or 0)
        local q = math.floor(pct * 50 + 0.5) / 50
        if obj.state.screw ~= q then
            obj.state.screw = q
            pcall(function() screw:set_pos(I(bx + 6 + (bw - 30) * (1 - q) * 0.28), I(by)) end)
        end
        local mq = math.floor(pct * 10 + 0.5) / 10
        if obj.state.melt == mq then return end
        obj.state.melt = mq
        -- 熔料：螺杆前端的橙带
        local mw = (bw - 30) * (0.10 + 0.42 * mq)
        local items2 = {}
        rect(items2, bx + 8, by + 10, mw, bh - 20, C.melt, 2, true, 60)
        rect(items2, bx + 8, by + 10, mw, bh - 20, theme.mix(C.melt, C.amber, 0.4), 2, false, 110)
        rect(items2, bx + 8, by + 10, math.max(4, mw * 0.35), bh - 20, theme.mix(C.melt, 0xFFD9A0, 0.5), 2, true, 70)
        pcall(function() melt_shape:set_items(items2) end)
    end
    obj.set_screw(1)

    -- 加热圈颜色：list 为 5 段的颜色
    function obj.set_heat(colors)
        local key = table.concat(colors, ",")
        if obj.state.heat == key then return end
        obj.state.heat = key
        local items3 = {}
        local seg = bw / #colors
        for i, col in ipairs(colors) do
            local x = bx + (i - 1) * seg + 2
            rect(items3, x, by - 5, seg - 4, 5, col, 1, true, 235)
            rect(items3, x, by + bh, seg - 4, 5, col, 1, true, 235)
        end
        pcall(function() heat_shape:set_items(items3) end)
    end

    -- 取件：visible 时制品从模具间落下
    function obj.set_part(visible, y)
        pcall(function()
            part:set_hidden(not visible)
            if visible then part:set_pos(I(FIX_X + 6), I(y or mid_y)) end
        end)
    end

    function obj.update(t)
        -- 制品下落：顶出阶段由页面驱动 set_part，这里只做细微呼吸，避免整块静止
    end

    function obj.destroy()
        pcall(function() static_shape:destroy() end)
        pcall(function() plate_shape:destroy() end)
        pcall(function() screw_shape:destroy() end)
        pcall(function() melt_shape:destroy() end)
        pcall(function() heat_shape:destroy() end)
        pcall(function() part_shape:destroy() end)
    end

    return obj
end

-- ===================== 成型周期环 =====================
--[[
七段圆弧代表七个阶段，弧长按各段时长分配。
当前阶段用亮色 + 外侧游标标出，其余段用暗色。
返回 { set(index, progress, colors) }
]]
function M.phase_ring(parent, cx, cy, r, stages, width)
    width = width or 16
    local total = 0
    for _, s in ipairs(stages) do total = total + s.dur end
    local shape
    local last_key = ""

    local function draw(idx, prog)
        local items = {}
        -- 底环
        arc(items, cx, cy, r, 0, 359, C.panel3, width, 255)
        local a = -90
        for i, s in ipairs(stages) do
            local span = 360 * s.dur / total
            local col = C.panel3
            local w = width
            if i < idx then
                col = theme.mix(s.color, C.bg0, 0.45)
            elseif i == idx then
                col = s.color
                w = width + 4
            else
                col = theme.mix(s.color, C.bg0, 0.78)
            end
            if span >= 1 then
                arc(items, cx, cy, r, I(a + 1), I(a + span - 1), col, w, (i == idx) and 255 or 200)
            end
            a = a + span
        end
        -- 当前角度游标
        if idx then
            local a2 = -90
            for i = 1, idx - 1 do a2 = a2 + 360 * stages[i].dur / total end
            a2 = a2 + 360 * stages[idx].dur / total * clamp01(prog)
            local rad = math.rad(a2)
            circle(items, cx + math.cos(rad) * r, cy + math.sin(rad) * r, width / 2 + 3,
                0xFFFFFF, true, 230, 1, 230)
        end
        if shape then
            pcall(function() shape:set_items(items) end)
        else
            shape = theme.shape(parent, 0, 0, cx * 2 + 4, cy * 2 + 4, items)
        end
    end

    draw(1, 0)
    local obj = { shape = shape }
    function obj.set(idx, prog)
        local key = tostring(idx) .. ":" .. tostring(math.floor((prog or 0) * 40))
        if key == last_key then return end
        last_key = key
        draw(idx, prog)
    end
    function obj.destroy() pcall(function() shape:destroy() end) end
    return obj
end

-- ===================== 曲线 =====================
local function catmull(p0, p1, p2, p3, t)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * ((2 * p1)
        + (p2 - p0) * t
        + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        + (3 * p1 - p0 - 3 * p2 + p3) * t3)
end

-- 稀疏样本按 Catmull-Rom 重采样，避免点对点直线画成台阶
function M.resample(hist, n_out)
    local out = {}
    local n = #hist
    if n < 2 or n_out < 2 then return out end
    local last = n_out - 1
    for k = 0, last do
        local fx = (n - 1) * k / last
        local i = math.floor(fx)
        if i > n - 2 then i = n - 2 end
        if i < 0 then i = 0 end
        local t = fx - i
        local i1 = i + 1
        out[k + 1] = catmull(hist[math.max(1, i1 - 1)], hist[i1],
                             hist[math.min(n, i1 + 1)], hist[math.min(n, i1 + 2)], t)
    end
    return out
end

--[[
多序列曲线。
series = { {data=, color=, min=, max=, width=, area=, area_opa=, log=, zero=}, ... }
opts   = { pad_top, pad_bottom, grid, bands = {{from,to,color,opacity}}, refs = {{y=0..1,color,dash}}, sample }
]]
function M.curve_items(w, h, series, opts)
    opts = opts or {}
    local pad_t = opts.pad_top or 10
    local pad_b = opts.pad_bottom or 14
    local ih = h - pad_t - pad_b
    local items = {}

    if opts.bands then
        for _, b in ipairs(opts.bands) do
            local x1 = I(b.from * w)
            local x2 = I(b.to * w)
            if x2 > x1 then
                items[#items + 1] = {
                    type = "rect", x = x1, y = pad_t, w = x2 - x1, h = ih,
                    color = b.color, width = 1, opacity = b.opacity or 14,
                    fill = true, fill_color = b.color, fill_opacity = b.opacity or 12,
                }
            end
        end
    end

    local grid = opts.grid or 4
    for i = 0, grid do
        local y = I(pad_t + ih * i / grid)
        line(items, 0, y, w, y, C.line, 1, 110)
    end
    for i = 1, 5 do
        local x = I(w * i / 6)
        line(items, x, pad_t, x, pad_t + ih, C.line, 1, 50)
    end

    if opts.refs then
        for _, r in ipairs(opts.refs) do
            local y = I(pad_t + ih - clamp01(r.y) * ih)
            line(items, 0, y, w, y, r.color or C.line2, 1, r.opacity or 120, r.dash or 5, r.gap or 5)
        end
    end

    for _, s in ipairs(series) do
        local n = #s.data
        if n >= 2 then
            local vmin, vmax = s.min or 0, s.max or 1
            if vmax - vmin < 0.000001 then vmax = vmin + 1 end
            local logmin = (vmin > 0) and math.log(vmin) or 0
            local logmax = (vmax > 0) and math.log(vmax) or 1

            local ys = {}
            for i = 1, n do
                local v = s.data[i] or vmin
                local k
                if s.log and v > 0 then
                    k = (math.log(v) - logmin) / math.max(0.000001, logmax - logmin)
                else
                    k = (v - vmin) / (vmax - vmin)
                end
                ys[i] = pad_t + ih - clamp01(k) * ih
            end
            local samples = M.resample(ys, math.max(2, math.floor(w / (opts.sample or 5))))

            if s.area then
                local dx = 8
                local zero_y = pad_t + ih
                if s.zero then
                    local kz = (0 - vmin) / (vmax - vmin)
                    zero_y = pad_t + ih - clamp01(kz) * ih
                end
                for x = 0, w - 1, dx do
                    local idx = math.min(#samples, math.max(1, math.floor(x / (w - 1) * (#samples - 1)) + 1))
                    local y = samples[idx]
                    local top, bot = math.min(y, zero_y), math.max(y, zero_y)
                    if bot - top > 1 then
                        items[#items + 1] = {
                            type = "rect", x = x, y = I(top), w = dx + 1, h = I(bot - top),
                            color = s.color, width = 1,
                            fill = true, fill_color = s.color, fill_opacity = s.area_opa or 20,
                        }
                    end
                end
            end

            for i = 2, #samples do
                local x1 = I((i - 2) / (#samples - 1) * (w - 1))
                local x2 = I((i - 1) / (#samples - 1) * (w - 1))
                line(items, x1, samples[i - 1], x2, samples[i], s.color, s.width or 2, s.opacity or 255)
            end

            if s.dot ~= false then
                local ly = samples[#samples]
                circle(items, w - 2, ly, 6, s.color, true, 45, 1, 45)
                circle(items, w - 2, ly, 3, 0xFFFFFF, true, 255, 1, 255)
            end
        end
    end

    return items
end

-- ===================== 温度柱 =====================
--[[
竖向温度柱：设定值刻度线 + 当前值填充。pct 为 0..1（相对量程）。
返回图元表，由页面在数值跨档时重建。
]]
function M.temp_column_items(w, h, pct, color, track, set_pct)
    local items = {}
    rect(items, 0, 0, w, h, track or C.panel3, 2, true, 255)
    local fh = I((h - 2) * clamp01(pct or 0))
    if fh > 1 then
        rect(items, 1, h - 1 - fh, w - 2, fh, color or C.amber, 2, true, 235)
    end
    if set_pct then
        local y = I(h - 1 - (h - 2) * clamp01(set_pct))
        line(items, -2, y, w + 2, y, C.ink2, 1, 200, 3, 3)
    end
    return items
end

-- ===================== 饼/环表 =====================
function M.ring_items(size, pct, color, track, width, start_angle)
    local c0 = math.floor(size / 2)
    local r = math.floor(size / 2 - 5)
    width = width or 6
    track = track or C.panel3
    start_angle = start_angle or -90
    local items = {
        { type = "arc", cx = c0, cy = c0, r = r, start_angle = 0, end_angle = 359,
          color = track, width = width, opacity = 255 },
    }
    pct = clamp01(pct or 0)
    if pct > 0.004 then
        items[#items + 1] = {
            type = "arc", cx = c0, cy = c0, r = r,
            start_angle = start_angle,
            end_angle = I(start_angle + 359.6 * pct),
            color = color, width = width, rounded = true,
        }
    end
    return items
end

-- ===================== 图标 =====================
--[[
kind: valve cylinder mold screw robot conveyor heater chiller plc
      di do ai ao ladder alarm gauge flow filter motor temp
      clock gear warn check play pause stop arrow dot shield
]]
function M.icon_items(kind, s, color)
    local items = {}
    local c = color or C.ink
    local mid = s / 2

    if kind == "valve" then
        -- 蝶阀：两个三角形 + 阀杆
        line(items, s * 0.16, s * 0.30, s * 0.16, s * 0.70, c, 2)
        line(items, s * 0.16, s * 0.30, s * 0.46, s * 0.50, c, 2)
        line(items, s * 0.16, s * 0.70, s * 0.46, s * 0.50, c, 2)
        line(items, s * 0.46, s * 0.50, s * 0.72, s * 0.32, c, 2)
        line(items, s * 0.46, s * 0.50, s * 0.72, s * 0.68, c, 2)
        line(items, s * 0.72, s * 0.32, s * 0.72, s * 0.68, c, 2)
        line(items, s * 0.46, s * 0.50, s * 0.46, s * 0.18, c, 2)
        line(items, s * 0.36, s * 0.18, s * 0.56, s * 0.18, c, 2)

    elseif kind == "cylinder" then
        rect(items, s * 0.12, s * 0.34, s * 0.46, s * 0.32, c, 2)
        line(items, s * 0.58, s * 0.50, s * 0.86, s * 0.50, c, 3)
        line(items, s * 0.74, s * 0.42, s * 0.86, s * 0.50, c, 2)
        line(items, s * 0.74, s * 0.58, s * 0.86, s * 0.50, c, 2)

    elseif kind == "mold" then
        rect(items, s * 0.14, s * 0.22, s * 0.28, s * 0.56, c, 2)
        rect(items, s * 0.58, s * 0.22, s * 0.28, s * 0.56, c, 2)
        line(items, s * 0.46, s * 0.36, s * 0.54, s * 0.36, c, 1)
        line(items, s * 0.46, s * 0.64, s * 0.54, s * 0.64, c, 1)

    elseif kind == "screw" then
        line(items, s * 0.14, s * 0.50, s * 0.86, s * 0.50, c, 2)
        for i = 0, 5 do
            local x = s * 0.20 + i * s * 0.11
            line(items, x, s * 0.34, x + s * 0.06, s * 0.66, c, 2)
        end

    elseif kind == "robot" then
        line(items, s * 0.18, s * 0.84, s * 0.34, s * 0.84, c, 2)
        line(items, s * 0.26, s * 0.84, s * 0.34, s * 0.48, c, 3)
        line(items, s * 0.34, s * 0.48, s * 0.72, s * 0.30, c, 3)
        line(items, s * 0.72, s * 0.30, s * 0.80, s * 0.52, c, 2)
        circle(items, s * 0.34, s * 0.48, 3, c, true)
        circle(items, s * 0.72, s * 0.30, 3, c, true)

    elseif kind == "conveyor" then
        circle(items, s * 0.22, s * 0.66, s * 0.10, c, false, 255, 2)
        circle(items, s * 0.78, s * 0.66, s * 0.10, c, false, 255, 2)
        line(items, s * 0.22, s * 0.50, s * 0.78, s * 0.50, c, 2)
        line(items, s * 0.22, s * 0.56, s * 0.78, s * 0.56, c, 1)
        rect(items, s * 0.40, s * 0.34, s * 0.14, s * 0.14, c, 1, true)

    elseif kind == "heater" then
        for i = 0, 3 do
            local x = s * 0.24 + i * s * 0.18
            local pts = {}
            for k = 0, 6 do
                pts[#pts + 1] = { x, s * 0.26 + k * s * 0.08 }
            end
            polyline(items, pts, c, 2, 200)
        end

    elseif kind == "chiller" then
        rect(items, s * 0.18, s * 0.22, s * 0.64, s * 0.56, c, 2)
        line(items, s * 0.30, s * 0.40, s * 0.52, s * 0.40, c, 2)
        line(items, s * 0.30, s * 0.56, s * 0.62, s * 0.56, c, 2)
        circle(items, s * 0.70, s * 0.38, 3, c, true)

    elseif kind == "plc" then
        rect(items, s * 0.12, s * 0.20, s * 0.56, s * 0.60, c, 2)
        line(items, s * 0.20, s * 0.32, s * 0.44, s * 0.32, c, 1)
        line(items, s * 0.20, s * 0.44, s * 0.44, s * 0.44, c, 1)
        line(items, s * 0.20, s * 0.56, s * 0.36, s * 0.56, c, 1)
        for i = 0, 3 do
            circle(items, s * 0.60, s * 0.28 + i * s * 0.14, 2, c, true)
        end
        line(items, s * 0.68, s * 0.50, s * 0.86, s * 0.50, c, 2)

    elseif kind == "di" or kind == "do" then
        rect(items, s * 0.12, s * 0.26, s * 0.76, s * 0.48, c, 2)
        for i = 0, 3 do
            circle(items, s * 0.26 + i * s * 0.16, s * 0.50, 2, c, true)
        end
        line(items, s * 0.12, s * 0.74, s * 0.12, s * 0.86, c, 2)
        line(items, s * 0.88, s * 0.74, s * 0.88, s * 0.86, c, 2)

    elseif kind == "ai" or kind == "ao" then
        local pts = {}
        for i = 0, 8 do
            local x = s * 0.10 + i * s * 0.10
            local y = s * 0.62 - math.sin(i / 8 * math.pi * 1.6) * s * 0.26
            pts[#pts + 1] = { x, y }
        end
        polyline(items, pts, c, 2, 230)
        line(items, s * 0.10, s * 0.78, s * 0.90, s * 0.78, c, 1)

    elseif kind == "ladder" then
        line(items, s * 0.12, s * 0.10, s * 0.12, s * 0.90, c, 2)
        line(items, s * 0.88, s * 0.10, s * 0.88, s * 0.90, c, 2)
        line(items, s * 0.12, s * 0.32, s * 0.44, s * 0.32, c, 2)
        line(items, s * 0.62, s * 0.32, s * 0.88, s * 0.32, c, 2)
        line(items, s * 0.44, s * 0.24, s * 0.44, s * 0.40, c, 2)
        line(items, s * 0.62, s * 0.24, s * 0.62, s * 0.40, c, 2)
        line(items, s * 0.12, s * 0.68, s * 0.40, s * 0.68, c, 2)
        line(items, s * 0.56, s * 0.68, s * 0.88, s * 0.68, c, 2)
        arc(items, s * 0.48, s * 0.68, s * 0.08, 0, 359, c, 2)

    elseif kind == "alarm" then
        arc(items, mid, s * 0.46, s * 0.28, 180, 360, c, 2)
        line(items, s * 0.22, s * 0.46, s * 0.22, s * 0.74, c, 2)
        line(items, s * 0.78, s * 0.46, s * 0.78, s * 0.74, c, 2)
        line(items, s * 0.12, s * 0.74, s * 0.88, s * 0.74, c, 2)
        line(items, mid, s * 0.10, mid, s * 0.16, c, 2)

    elseif kind == "gauge" then
        arc(items, mid, s * 0.70, s * 0.34, 200, 340, c, 2)
        line(items, mid, s * 0.70, mid + s * 0.18, s * 0.44, c, 2)
        circle(items, mid, s * 0.70, 2, c, true)

    elseif kind == "flow" then
        line(items, s * 0.10, s * 0.40, s * 0.62, s * 0.40, c, 2)
        line(items, s * 0.62, s * 0.40, s * 0.50, s * 0.30, c, 2)
        line(items, s * 0.62, s * 0.40, s * 0.50, s * 0.50, c, 2)
        line(items, s * 0.10, s * 0.66, s * 0.62, s * 0.66, c, 2)
        line(items, s * 0.62, s * 0.66, s * 0.50, s * 0.56, c, 2)
        line(items, s * 0.62, s * 0.66, s * 0.50, s * 0.76, c, 2)
        line(items, s * 0.74, s * 0.20, s * 0.74, s * 0.84, c, 1)

    elseif kind == "filter" then
        line(items, s * 0.12, s * 0.26, s * 0.88, s * 0.26, c, 2)
        line(items, s * 0.12, s * 0.26, s * 0.34, s * 0.78, c, 2)
        line(items, s * 0.88, s * 0.26, s * 0.66, s * 0.78, c, 2)
        line(items, s * 0.34, s * 0.78, s * 0.66, s * 0.78, c, 2)
        for i = 1, 3 do
            line(items, s * (0.12 + i * 0.06), s * (0.38 + i * 0.04), s * (0.88 - i * 0.06), s * (0.38 + i * 0.04), c, 1)
        end

    elseif kind == "motor" then
        circle(items, mid, mid, s * 0.30, c, false, 255, 2)
        line(items, mid - s * 0.14, mid, mid + s * 0.14, mid, c, 2)
        line(items, mid, mid - s * 0.14, mid, mid + s * 0.14, c, 2)
        line(items, s * 0.80, mid, s * 0.92, mid, c, 2)

    elseif kind == "temp" then
        rect(items, mid - s * 0.08, s * 0.12, s * 0.16, s * 0.50, c, 5)
        circle(items, mid, s * 0.72, s * 0.14, c, true, 255, 1, 255)
        line(items, mid, s * 0.34, mid, s * 0.62, c, 2)

    elseif kind == "clock" then
        circle(items, mid, mid, s * 0.38, c, false, 255, 2)
        line(items, mid, mid, mid, s * 0.26, c, 2)
        line(items, mid, mid, s * 0.68, mid, c, 2)

    elseif kind == "gear" then
        circle(items, mid, mid, s * 0.26, c, false, 255, 2)
        circle(items, mid, mid, s * 0.08, c, false, 255, 2)
        for i = 0, 5 do
            local a = math.pi * 2 * i / 6 - math.pi / 2
            line(items, mid + math.cos(a) * s * 0.28, mid + math.sin(a) * s * 0.28,
                mid + math.cos(a) * s * 0.42, mid + math.sin(a) * s * 0.42, c, 2)
        end

    elseif kind == "warn" then
        line(items, mid, s * 0.12, s * 0.12, s * 0.84, c, 2)
        line(items, s * 0.12, s * 0.84, s * 0.88, s * 0.84, c, 2)
        line(items, s * 0.88, s * 0.84, mid, s * 0.12, c, 2)
        line(items, mid, s * 0.38, mid, s * 0.60, c, 2)
        circle(items, mid, s * 0.71, 1, c, true)

    elseif kind == "check" then
        line(items, s * 0.18, s * 0.52, s * 0.42, s * 0.76, c, 3)
        line(items, s * 0.42, s * 0.76, s * 0.82, s * 0.24, c, 3)

    elseif kind == "play" then
        line(items, s * 0.30, s * 0.18, s * 0.30, s * 0.82, c, 2)
        line(items, s * 0.30, s * 0.18, s * 0.80, mid, c, 2)
        line(items, s * 0.80, mid, s * 0.30, s * 0.82, c, 2)

    elseif kind == "pause" then
        rect(items, s * 0.28, s * 0.20, s * 0.14, s * 0.60, c, 1, true)
        rect(items, s * 0.58, s * 0.20, s * 0.14, s * 0.60, c, 1, true)

    elseif kind == "stop" then
        rect(items, s * 0.26, s * 0.26, s * 0.48, s * 0.48, c, 3, true)

    elseif kind == "arrow" then
        line(items, s * 0.12, mid, s * 0.78, mid, c, 2)
        line(items, s * 0.78, mid, s * 0.58, mid - s * 0.18, c, 2)
        line(items, s * 0.78, mid, s * 0.58, mid + s * 0.18, c, 2)

    elseif kind == "shield" then
        line(items, mid, s * 0.10, s * 0.82, s * 0.28, c, 2)
        line(items, s * 0.82, s * 0.28, s * 0.82, s * 0.56, c, 2)
        line(items, s * 0.82, s * 0.56, mid, s * 0.90, c, 2)
        line(items, mid, s * 0.90, s * 0.18, s * 0.56, c, 2)
        line(items, s * 0.18, s * 0.56, s * 0.18, s * 0.28, c, 2)
        line(items, s * 0.18, s * 0.28, mid, s * 0.10, c, 2)
    end

    return items
end

function M.icon(parent, kind, x, y, s, color)
    local items = M.icon_items(kind, s, color)
    if #items == 0 then return nil end
    return theme.shape(parent, x, y, s, s, items)
end

-- 图标 + 底色方块
function M.icon_badge(parent, x, y, size, kind, color, bg, bg_opa, icon_pad)
    local box = theme.box(parent, x, y, size, size, bg or C.panel3, math.floor(size / 4), bg_opa)
    local pad = icon_pad or math.floor(size * 0.26)
    local ic = M.icon(parent, kind, x + pad, y + pad, size - pad * 2, color or C.ink)
    return box, ic
end

-- ===================== 小部件 =====================
function M.dot(parent, x, y, r, color)
    return theme.shape(parent, x - r, y - r, r * 2, r * 2, {
        { type = "circle", cx = r, cy = r, r = r, color = color, width = 1,
          fill = true, fill_color = color, fill_opacity = 255 },
    })
end

-- 刻度尺：底部时间轴的短竖线
function M.ticks_items(w, n, color, len)
    local items = {}
    for i = 0, n do
        local x = math.floor(w * i / n)
        line(items, x, 0, x, len or 4, color or C.line, 1, 140)
    end
    return items
end

return M
