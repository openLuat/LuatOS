--[[
@module  ui_wheel
@summary 今天吃什么 - 通用转盘组件（矢量盘面 + 扫光带 + 编号高亮 + 停靠动画）
@version 1.0
@date    2026.10.26
@usage
local wheel = require "ui_wheel"
local w = ui_wheel.new({
    parent = page_box,
    rings  = T.rings.home,              -- 1 环或 3 环，规格见 ui_theme
    button_text = "开始配餐",
    on_button = function() ... end,     -- 点击中心按钮（回调里自己开协程）
})

-- 下面这些必须在协程里调用（内部 sys.wait）
w:spin_to(1, 17, { duration = 3200, turns = 4 })   -- 停在第 17 个扇区
w:mark_hit(1, 17)                                  -- 落点高亮（可多次调用，家常菜连停 5 次）
w:reset_hits()                                     -- 清掉所有高亮，开新的一轮之前调用

=== 五层结构（z 序：盘面 → 高亮层 → 扫光带 → 编号 → 中心毂）===
1、盘面 shape：整盘图元（盘体 + 所有扇区胶囊 + 中心毂圈 + 盘边灯泡），只在建盘、
   落点高亮（其余扇区压暗）时 set_items，每帧不动它。
2、高亮层 shape：**小对象**，只盖住当选扇区那一小块；不再整盘重绘，
   否则 50~80 个图元会被连带重画一遍。
3、扫光带 shape：**小对象**，每帧 set_pos + set_items 挪到当前角度，
   脏区只有 2 个 156x156 的方块，这是整屏唯一的逐帧动画开销来源。
   它压在编号下面：光带扫过时编号仍然读得清，停稳后也不会把结果编号挡掉。
4、编号 label：每个扇区一个小文本框，只有「当前扫过」和「最终命中」会改颜色，
   其余时候一个字节都不动，避免每帧刷 50~80 个 label。
5、中心毂 + 圆形主按钮：最后创建，盖住扫光带的内端。

=== 角度约定 ===
0 度在 12 点方向、顺时针为正；扇区 k（1 起）覆盖
[(k-1)*step, k*step)，中心角 = (k-0.5)*step。所以「停在第 k 个扇区」
就是让扫光带停在 (k-0.5)*step 上，判定与动画共用同一套公式，不会差一格。
]]

local T = require "ui_theme"
local D = require "ui_draw"

local C = T.c
local W = {}
W.__index = W

local function seg_points(p, cx, cy)
    if p.radial then
        local x1, y1 = D.polar(cx, cy, p.r0, p.a)
        local x2, y2 = D.polar(cx, cy, p.r1, p.a)
        return x1, y1, x2, y2
    end
    local x1, y1 = D.polar(cx, cy, p.r, p.a0)
    local x2, y2 = D.polar(cx, cy, p.r, p.a1)
    return x1, y1, x2, y2
end

--[[把环规格展开成「每个扇区 = 若干条胶囊」的极坐标数据
一次算好，之后建盘 / 高亮 / 落点判定都复用，避免三处各算一套角度导致接缝错位。]]
local function build_cells(ring)
    local step = 360 / ring.count
    local cells = {}
    local cxm = ring.r0 + ring.r1
    local mid_r = cxm / 2
    for k = 1, ring.count do
        local a0 = (k - 1) * step
        local am = a0 + step / 2
        local list = {}
        if ring.style == "radial" then
            list[1] = {
                radial = true, a = am,
                r0 = ring.r0 + ring.w / 2,
                r1 = ring.r1 - ring.w / 2,
            }
        else
            local segs = ring.segs or 1
            local seg_step = step / segs
            -- 段与段之间留 1.6 度左右的缝（按半径折算成固定像素缝，视觉更齐）
            local gap = math.deg(1.8 / mid_r)
            for s = 0, segs - 1 do
                local sa = a0 + s * seg_step + gap
                local sb = a0 + (s + 1) * seg_step - gap
                if sb > sa then
                    list[#list + 1] = { r = mid_r, a0 = sa, a1 = sb }
                end
            end
        end
        cells[k] = list
    end
    return cells, step
end

-- 当选扇区那一块的包围盒边长（高亮层小对象要多大）
local function cell_box(ring, step)
    local span
    if ring.style == "radial" then
        span = ring.r1 - ring.r0
    else
        span = 2 * (ring.r0 + ring.r1) / 2 * math.sin(math.rad(step / 2))
    end
    return math.floor(math.sqrt(span * span + ring.w * ring.w) + 14)
end

function W.new(opts)
    local self = setmetatable({}, W)
    self.parent = opts.parent
    self.cx, self.cy = T.wheel.cx, T.wheel.cy
    self.rings = opts.rings
    self.on_button = opts.on_button
    self.angle = 0
    self.cur = {}
    self.labels = {}
    self.winners = {}   -- winners[环][扇区] = true
    self.busy = false

    local PL = T.wheel.r_plate
    self.PL = PL

    -- 展开环数据
    self.cells = {}
    local box = 0
    for ri, ring in ipairs(self.rings) do
        local cells, step = build_cells(ring)
        self.cells[ri] = cells
        ring.step = step
        local b = cell_box(ring, step)
        ring.box = b
        if b > box then box = b end
    end
    self.box = box

    -- 1、盘面
    self.shape = D.shape(self.parent, self.cx - PL, self.cy - PL, PL * 2, PL * 2, {})
    -- 2、落点高亮层（小对象，按需挪位置）
    --    注意 z 序：高亮层在编号**下面**，白芯才不会把编号盖掉
    self.overlay = D.shape(self.parent, 0, 0, box, box, {})
    -- 3、扫光带（在编号**下面**：光带扫过时编号仍然可读，停稳后也不会挡住结果编号）
    local sb = T.wheel.sweep_box
    self.sweep = D.shape(self.parent, self.cx - sb / 2, self.cy - sb / 2, sb, sb, {})
    -- 4、编号
    for ri, ring in ipairs(self.rings) do
        local labels = {}
        for k = 1, ring.count do
            local am = (k - 0.5) * ring.step
            local x, y = D.polar(self.cx, self.cy, ring.num_r, am)
            labels[k] = D.label_mid(self.parent, x - ring.num_w / 2, y, ring.num_w,
                string.format("%02d", k), ring.num_font, C.num, D.ALIGN_CENTER)
        end
        self.labels[ri] = labels
        self.cur[ri] = 0
    end
    -- 5、中心毂 + 圆形主按钮
    local H = T.wheel.r_hub
    D.box(self.parent, self.cx - H, self.cy - H, H * 2, H * 2,
        { color = C.hub_ring, radius = H })
    local H2 = H - 6
    D.box(self.parent, self.cx - H2, self.cy - H2, H2 * 2, H2 * 2,
        { color = C.hub, radius = H2 })
    local B = T.wheel.r_btn
    self.btn = D.button(self.parent, self.cx - B, self.cy - B, B * 2, B * 2,
        opts.button_text or "开饭", T.f.mid,
        { bg = C.accent, text_color = C.white, radius = B, on_click = opts.on_button })

    self:render_disc()
    self:set_button(opts.button_text or "开饭", false)
    return self
end

-- ==================== 盘面 ====================

--[[重画整盘
self.winners[环][扇区] = true 记着所有已选中的格子：有选中时其余扇区压暗，
视线自然落到当选格上；家常菜连停 5 次时前面几道也保持高亮。]]
function W:render_disc()
    local PL = self.PL
    local items = {}
    local any = next(self.winners) ~= nil
    items[1] = D.disc(PL, PL, T.wheel.r_plate, C.plate)
    for ri, ring in ipairs(self.rings) do
        local cells = self.cells[ri]
        local wset = self.winners[ri]
        for k = 1, ring.count do
            local win = wset and wset[k]
            local opa = (any and not win) and 186 or 255
            local color = (k % 2 == 1) and ring.colorA or ring.colorB
            for _, p in ipairs(cells[k]) do
                local x1, y1, x2, y2 = seg_points(p, PL, PL)
                items[#items + 1] = D.capsule(x1, y1, x2, y2, ring.w, color, opa)
            end
        end
    end
    -- 中心毂底（在扇区内沿之上，压住胶囊的圆头）
    items[#items + 1] = D.disc(PL, PL, T.wheel.r_hub + 8, C.hub_ring)
    items[#items + 1] = D.disc(PL, PL, T.wheel.r_hub, C.hub)
    -- 盘边小灯泡
    local n = T.wheel.bulbs
    for i = 0, n - 1 do
        local x, y = D.polar(PL, PL, T.wheel.bulb_ring, i * 360 / n)
        local color = (i % 2 == 0) and C.yellow or C.white
        items[#items + 1] = D.disc(x, y, T.wheel.bulb_r, color, 235)
    end
    self.shape:set_items(items)
end

-- ==================== 扫光带 / 编号 ====================

function W:set_angle(deg)
    deg = deg % 360
    self.angle = deg

    local sb = T.wheel.sweep_box
    local half = sb / 2
    local rad = math.rad(deg)
    local dx, dy = math.sin(rad), -math.cos(rad)
    local rmid = (T.wheel.r_in + T.wheel.r_out) / 2
    local mx = self.cx + rmid * dx
    local my = self.cy + rmid * dy
    D.set_pos(self.sweep, mx - half, my - half)

    local L = T.wheel.sweep_len / 2
    local x1, y1 = half - L * dx, half - L * dy
    local x2, y2 = half + L * dx, half + L * dy
    self.sweep:set_items({
        D.capsule(x1, y1, x2, y2, 34, C.white, 40),   -- 外发光
        D.capsule(x1, y1, x2, y2, 12, C.white, 205),  -- 亮芯
        D.disc(x2, y2, 7, C.white, 235),              -- 光头
        D.disc(x1, y1, 4, C.white, 110),              -- 尾巴
    })

    -- 编号逐个点亮：只有扇区变化时才改颜色，避免每帧刷 label
    for ri, ring in ipairs(self.rings) do
        local k = math.floor(deg / ring.step) + 1
        if k < 1 then k = 1 end
        if k > ring.count then k = ring.count end
        local old = self.cur[ri]
        if old ~= k then
            if old and old > 0 and self.labels[ri][old] then
                self.labels[ri][old]:set_color(C.num)
            end
            self.labels[ri][k]:set_color(C.num_hot)
            self.cur[ri] = k
        end
    end
end

-- 落点高亮：当选扇区套一圈橙边 + 白芯，其余扇区压暗
function W:mark_hit(ring_index, sector)
    local ring = self.rings[ring_index]
    if not ring then return end
    local cells = self.cells[ring_index][sector]
    if not cells then return end

    self.winners[ring_index] = self.winners[ring_index] or {}
    self.winners[ring_index][sector] = true
    self:render_disc()

    -- 高亮层是个小对象，按当选格重新定位
    local box = ring.box
    local am = (sector - 0.5) * ring.step
    local ox, oy = D.polar(self.cx, self.cy, ring.num_r, am)
    local origin_x = ox - box / 2
    local origin_y = oy - box / 2
    D.set_pos(self.overlay, origin_x, origin_y)

    -- 需要换算到高亮层的局部坐标：盘心在局部坐标系里的位置
    local lcx = self.cx - origin_x
    local lcy = self.cy - origin_y
    local items = {}
    for _, p in ipairs(cells) do
        local x1, y1, x2, y2 = seg_points(p, lcx, lcy)
        items[#items + 1] = D.capsule(x1, y1, x2, y2, ring.w + 7, C.accent, 255)
    end
    for _, p in ipairs(cells) do
        local x1, y1, x2, y2 = seg_points(p, lcx, lcy)
        items[#items + 1] = D.capsule(x1, y1, x2, y2, ring.w, C.white, 238)
    end
    self.overlay:set_items(items)

    -- 当选编号染成强调色
    local lb = self.labels[ring_index][sector]
    if lb then lb:set_color(C.accent) end
end

-- 清掉所有落点高亮（每次开新的一轮之前调用）
function W:reset_hits()
    for ri, set in pairs(self.winners) do
        for k in pairs(set) do
            local lb = self.labels[ri] and self.labels[ri][k]
            if lb then lb:set_color(C.num) end
        end
    end
    self.winners = {}
    self.overlay:set_items({})
    self:render_disc()
end

-- ==================== 按钮 ====================

function W:set_button(text, disabled)
    if self.btn then
        self.btn:set_text(text)
        self.btn:set_disabled(disabled and true or false)
    end
end

-- ==================== 停靠动画 ====================

--[[转到第 sector 个扇区（ring_index 环），必须在协程里调用
opts.duration 毫秒、opts.turns 额外圈数]]
function W:spin_to(ring_index, sector, opts)
    opts = opts or {}
    local ring = self.rings[ring_index]
    local target = (sector - 0.5) * ring.step
    local from = self.angle % 360
    local delta = ((target - from) % 360) + 360 * (opts.turns or 4)
    local dur = opts.duration or 3200
    local frame = T.wheel.frame_ms

    local t = 0
    while t < dur do
        sys.wait(frame)
        t = t + frame
        local p = D.ease_out_cubic(math.min(1, t / dur))
        self:set_angle(from + delta * p)
    end
    self:set_angle(target)
end

return W
