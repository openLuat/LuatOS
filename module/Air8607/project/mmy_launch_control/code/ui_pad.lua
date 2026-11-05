--[[
@module  ui_pad
@summary 发射台视图：夜空 / 塔架 / 箭体 / 火焰 / 烟雾 / 相机跟随 / 底部遥测条
@version 1.0
@date    2026.11.04

三层结构（只改需要动的那层）：
  bg  层  天空渐变 + 星点（静态）
  mid 层  地面 / 远山 / 发射台 / 塔架（容器整体下移做"相机跟随"）
  top 层  箭体 / 尾焰 / 烟雾 / 卫星（每帧重画，图元约 90 个）

箭体没有 polygon 图元，用 2px 高横条逐行堆出来，
好处是重力转弯只要对每行做一次水平错切换算。
]]
local conf    = require "conf"
local theme   = require "theme"
local kit     = require "kit"
local mission = require "mission"

local C = theme.C
local M = {}

local W, H   = 328, 456
local GROUND = 352
local RCX    = 190
local RBASE  = 336

-- 装配用图元容器
local items = {}
local function push(it) items[#items + 1] = it end

-- ==================== 静态场景 ====================
local function build_bg(parent)
    local it = {}
    local bands = 14
    for i = 0, bands - 1 do
        local t = i / (bands - 1)
        local col = theme.lerp_color(C.sky1, C.sky2, t)
        it[#it + 1] = { type = "rect", x = 0, y = math.floor(i * GROUND / bands),
            w = W, h = math.ceil(GROUND / bands) + 1, radius = 0, color = col,
            width = 0, fill = true, fill_color = col, fill_opacity = 255 }
    end
    it[#it + 1] = { type = "rect", x = 0, y = GROUND - 50, w = W, h = 50,
        radius = 0, color = C.amber, width = 0, fill = true,
        fill_color = C.amber, fill_opacity = 11 }
    -- 星点（固定种子，保证每次开机一致）
    local seed = 20261104
    local function rnd()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end
    for _ = 1, 34 do
        it[#it + 1] = { type = "circle", cx = math.floor(rnd() * W),
            cy = math.floor(rnd() * (GROUND - 96)),
            r = rnd() < 0.12 and 2 or 1, color = 0xBFD6FF, width = 0,
            fill = true, fill_color = 0xBFD6FF, fill_opacity = 70 + math.floor(rnd() * 130) }
    end
    return theme.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = it })
end

local function build_scene(parent)
    local it = {}
    it[#it + 1] = { type = "rect", x = -8, y = GROUND, w = W + 16, h = H - GROUND + 8,
        radius = 0, color = C.ground, width = 0, fill = true,
        fill_color = C.ground, fill_opacity = 255 }
    it[#it + 1] = { type = "line", x1 = 0, y1 = GROUND, x2 = W, y2 = GROUND,
        color = 0x1B2E45, width = 1 }
    kit.triangle_up(it, 52, GROUND - 26, 46, GROUND, 0x0A111C, 255)
    kit.triangle_up(it, 286, GROUND - 16, 54, GROUND, 0x0A111C, 255)
    it[#it + 1] = { type = "rect", x = 96, y = GROUND - 8, w = 196, h = 8,
        radius = 2, color = 0x1A2839, width = 0, fill = true,
        fill_color = 0x1A2839, fill_opacity = 255 }

    -- 塔架
    local tx1, tx2 = 116, 146
    for _, x in ipairs({ tx1, tx2 }) do
        it[#it + 1] = { type = "line", x1 = x, y1 = 104, x2 = x, y2 = GROUND - 8,
            color = C.tower, width = 2 }
    end
    local y = GROUND - 22
    while y > 112 do
        it[#it + 1] = { type = "line", x1 = tx1, y1 = y, x2 = tx2, y2 = y,
            color = C.tower, width = 1, opacity = 210 }
        it[#it + 1] = { type = "line", x1 = tx1, y1 = y, x2 = tx2, y2 = y - 20,
            color = C.tower, width = 1, opacity = 110 }
        it[#it + 1] = { type = "line", x1 = tx1, y1 = y - 20, x2 = tx2, y2 = y,
            color = C.tower, width = 1, opacity = 110 }
        y = y - 22
    end
    it[#it + 1] = { type = "line", x1 = tx1, y1 = 104, x2 = tx2, y2 = 104,
        color = C.tower, width = 2 }
    it[#it + 1] = { type = "line", x1 = tx2, y1 = 186, x2 = RCX - 16, y2 = 186,
        color = 0x2C4058, width = 4 }
    it[#it + 1] = { type = "line", x1 = tx2, y1 = 262, x2 = RCX - 16, y2 = 262,
        color = 0x2C4058, width = 3 }
    -- 塔顶红灯
    it[#it + 1] = { type = "circle", cx = 131, cy = 100, r = 3, color = C.red,
        width = 0, fill = true, fill_color = C.red, fill_opacity = 230 }

    return theme.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = it })
end

-- ==================== 箭体 ====================
local function body_hw(y)
    if y > -8 then return 7 + (y + 8) / 8 * 2 end
    if y > -80 then return 15 end
    if y > -104 then return 12 end
    local t = (y + 104) / -34
    return math.max(0, 12 * (1 - t * t))
end

local function body_color(y)
    if y > -8 then return 0x2A3547 end
    if y > -80 then
        if y <= -32 and y > -36 then return C.amber end
        if y <= -62 and y > -65 then return 0x8FA6BE end
        return 0xE7EFF8
    end
    if y > -104 then return 0xCFDCEA end
    if y <= -132 then return C.amber end
    return 0xE7EFF8
end

local function draw_rocket(cx, base, tilt, stage2)
    local tan = math.tan(math.rad(tilt or 0))
    kit.tri_side(items, cx - 15, base - 26, 13, 22, -1, 0xC9D8E8, 255)
    kit.tri_side(items, cx + 15, base - 26, 13, 22, 1, 0xC9D8E8, 255)
    for y = -2, -136, -2 do
        local w = math.floor(body_hw(y) * 2 + 0.5)
        if w >= 1 then
            local dx = math.floor((-y) * tan + 0.5)
            local col = body_color(y)
            push({ type = "rect", x = cx - math.floor(w / 2) + dx, y = base + y,
                w = w, h = 2, radius = 0, color = col, width = 0,
                fill = true, fill_color = col, fill_opacity = 255 })
        end
    end
    if stage2 then
        push({ type = "rect", x = cx - 6, y = base - 110, w = 12, h = 4, radius = 1,
            color = 0x2A3547, width = 0, fill = true, fill_color = 0x2A3547,
            fill_opacity = 255 })
    end
    push({ type = "rect", x = cx - 3, y = base - 120, w = 6, h = 5, radius = 1,
        color = C.cyan, width = 0, fill = true, fill_color = C.cyan, fill_opacity = 200 })
end

local function draw_flame(cx, base, ignite, now)
    if ignite <= 0.02 then return end
    local flick = 0.82 + 0.18 * math.sin(now * 21) + 0.08 * math.sin(now * 37)
    local len = (34 + 46 * flick) * ignite
    local rx = 10 + 5 * ignite
    push({ type = "ellipse", cx = cx, cy = base + len * 0.42, rx = rx + 4,
        ry = len * 0.55, color = C.amber, width = 0, fill = true,
        fill_color = C.amber, fill_opacity = 46 })
    push({ type = "ellipse", cx = cx, cy = base + len * 0.40, rx = rx, ry = len * 0.50,
        color = C.amber, width = 0, fill = true, fill_color = C.amber, fill_opacity = 190 })
    push({ type = "ellipse", cx = cx, cy = base + len * 0.30, rx = rx * 0.62,
        ry = len * 0.34, color = C.amber2, width = 0, fill = true,
        fill_color = C.amber2, fill_opacity = 240 })
    push({ type = "ellipse", cx = cx, cy = base + len * 0.18, rx = rx * 0.34,
        ry = len * 0.20, color = 0xFFF6E0, width = 0, fill = true,
        fill_color = 0xFFF6E0, fill_opacity = 250 })
    for i = 1, 3 do
        local off = math.sin(now * (13 + i * 4) + i) * (5 + i * 2)
        push({ type = "circle", cx = cx + off, cy = base + len * (0.72 + i * 0.12),
            r = math.max(2, rx * (0.32 - i * 0.06)), color = C.amber, width = 0,
            fill = true, fill_color = C.amber, fill_opacity = 170 - i * 40 })
    end
end

-- 台面烟云（跟着地面一起下沉）
local function draw_smoke(cx, ignite, now, scroll)
    if ignite <= 0.06 then return end
    local y0 = GROUND + scroll
    for i = 1, 8 do
        local ph = (now * 0.75 + i * 0.13) % 1
        local dir = (i % 2 == 0) and 1 or -1
        local x = cx + dir * (12 + ph * (44 + i * 5))
        local y = y0 + 10 - ph * 22
        push({ type = "circle", cx = math.floor(x), cy = math.floor(y),
            r = math.floor(5 + ph * 14), color = 0xDCE6F2, width = 0,
            fill = true, fill_color = 0xDCE6F2,
            fill_opacity = math.floor(110 * (1 - ph) * ignite) })
    end
end

-- 入轨后的卫星图标
local function draw_satellite(cx, cy, now)
    local dx = math.floor(math.sin(now * 0.8) * 6)
    local x = cx + dx
    -- 太阳翼
    push({ type = "rect", x = x - 54, y = cy - 7, w = 34, h = 14, radius = 2,
        color = C.blue, width = 1, fill = true, fill_color = C.blue, fill_opacity = 90 })
    push({ type = "rect", x = x + 20, y = cy - 7, w = 34, h = 14, radius = 2,
        color = C.blue, width = 1, fill = true, fill_color = C.blue, fill_opacity = 90 })
    push({ type = "line", x1 = x - 20, y1 = cy, x2 = x - 9, y2 = cy, color = 0x89A4C4, width = 2 })
    push({ type = "line", x1 = x + 9, y1 = cy, x2 = x + 20, y2 = cy, color = 0x89A4C4, width = 2 })
    -- 星体
    push({ type = "rect", x = x - 9, y = cy - 11, w = 18, h = 22, radius = 3,
        color = 0xE7EFF8, width = 0, fill = true, fill_color = 0xE7EFF8, fill_opacity = 255 })
    push({ type = "rect", x = x - 9, y = cy - 3, w = 18, h = 4, radius = 1,
        color = C.amber, width = 0, fill = true, fill_color = C.amber, fill_opacity = 230 })
    -- 天线
    push({ type = "line", x1 = x, y1 = cy - 11, x2 = x, y2 = cy - 20, color = 0xB9C9DC, width = 1 })
    push({ type = "circle", cx = x, cy = cy - 21, r = 2, color = C.green, width = 0,
        fill = true, fill_color = C.green, fill_opacity = 255 })
end

-- ==================== 画面构建 ====================
--- 构建发射台卡片内部
-- @param userdata parent 卡片容器
function M.build(parent)
    local self = { now = 0, scroll = 0, acc = 0 }

    build_bg(parent)

    -- 场景层（会整体下移）
    local mid = theme.box(parent, 0, 0, W, H, 0x000000, 0, 0)
    build_scene(mid)
    self.mid = mid

    -- 动态层
    self.top = theme.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })

    -- 顶部标题
    theme.label(parent, 14, 10, 180, 20, "发射台 · 39A", 14, C.ink2)
    local pill_box = theme.box(parent, 208, 10, 104, 24, C.cyan, 12, 40)
    local pill_tx = theme.label(pill_box, 0, 3, 104, 20, "待命", 12, C.cyan,
        airui.TEXT_ALIGN_CENTER)
    self.pill_box, self.pill_tx = pill_box, pill_tx

    -- 底部遥测条
    local hy = 358
    local hud = theme.frame(parent, 12, hy, 304, 86, C.panel2, 10, C.line, 1, 238)
    local cells = {
        { cap = "高度 km",   color = C.cyan },
        { cap = "速度 m/s",  color = C.ink },
        { cap = "过载 g",    color = C.amber },
    }
    self.vals = {}
    for i, cell in ipairs(cells) do
        local cx = 6 + (i - 1) * 98
        theme.label(hud, cx, 10, 92, 14, cell.cap, 11, C.ink3)
        self.vals[i] = theme.label(hud, cx, 26, 96, 30, "--", 22, cell.color)
        if i > 1 then
            theme.box(hud, cx - 6, 12, 1, 58, C.line, 0, 200)
        end
    end
    -- 底部一行小字：任务时间
    self.sub = theme.label(hud, 6, 62, 290, 16, "任务时间 --", 11, C.ink3)

    -- 中央横幅（入轨 / 中止）
    local banner = theme.box(parent, 34, 96, 244, 44, C.green, 8, 44)
    self.banner_tx = theme.label(banner, 0, 11, 244, 24, "载荷入轨", 18, C.green,
        airui.TEXT_ALIGN_CENTER)
    banner:set_hidden(true)
    self.banner, self.banner_color = banner, C.green

    return self
end

-- ==================== 每帧刷新 ====================
local PHASE_STYLE = {
    standby   = { "待命",   C.ink2 },
    check     = { "自检中", C.cyan },
    countdown = { "倒计时", C.amber },
    ascent    = { "上升段", C.amber },
    orbit     = { "已入轨", C.green },
    abort     = { "已中止", C.red },
}

function M.tick(self, dt)
    self.now = self.now + dt
    local st = mission.st

    -- ---------- 相机 ----------
    local scroll = 0
    if st.phase == "ascent" or st.phase == "orbit" then
        scroll = 250 * kit.ease_out(kit.clamp(st.mt / 8, 0, 1))
    end
    if math.abs(scroll - self.scroll) >= 2 then
        self.scroll = scroll
        self.mid:move(0, math.floor(scroll))
    end

    -- ---------- 箭体位置 ----------
    local base = RBASE
    if st.phase == "ascent" or st.phase == "orbit" then
        base = RBASE - 96 * kit.ease_out(kit.clamp(st.mt / 4, 0, 1))
    end

    -- ---------- 动态图元 ----------
    for i = #items, 1, -1 do items[i] = nil end
    if st.phase == "orbit" then
        draw_satellite(RCX, 190, self.now)
    else
        draw_rocket(RCX, base, st.tilt, st.stage2)
        draw_flame(RCX, base, st.ignite, self.now)
        draw_smoke(RCX, st.ignite, self.now, self.scroll)
    end

    -- 上升段的速度条纹（越往上越快）
    if st.phase == "ascent" and st.vel > 320 then
        local sp = 0.02 * st.vel
        for i = 1, 10 do
            local x = 18 + ((i * 97) % 292)
            local len = 14 + st.vel / 55
            local y = ((self.now * sp + i * 57) % (H + 150)) - 75
            push({ type = "line", x1 = x, y1 = math.floor(y), x2 = x,
                y2 = math.floor(y + len), color = 0xBFD6FF, width = 1, opacity = 55 })
        end
    end

    -- 待命时的液氧排气白雾
    if st.phase == "standby" or st.phase == "check" then
        for i = 1, 3 do
            local ph = (self.now * 0.16 + i * 0.33) % 1
            push({ type = "circle", cx = RCX - 12 + i * 5,
                cy = math.floor(base - 92 - ph * 54), r = 2 + math.floor(ph * 3),
                color = 0xCFE4FF, width = 0, fill = true, fill_color = 0xCFE4FF,
                fill_opacity = math.floor(46 * (1 - ph)) })
        end
    end

    theme.set_items(self.top, items)

    -- ---------- 状态胶囊 ----------
    local ps = PHASE_STYLE[st.phase] or PHASE_STYLE.standby
    if self.pill_text ~= ps[1] then
        self.pill_text = ps[1]
        self.pill_tx:set_text(ps[1])
        self.pill_box:set_color(ps[2], 40)
        self.pill_tx:set_color(ps[2])
    end

    -- ---------- 横幅 ----------
    if st.phase == "orbit" then
        if self.banner_text ~= "载荷入轨 · 200 km" then
            self.banner_text = "载荷入轨 · 200 km"
            self.banner_tx:set_text(self.banner_text)
            self.banner:set_color(C.green, 44)
            self.banner_tx:set_color(C.green)
            self.banner:set_hidden(false)
        end
    elseif st.phase == "abort" then
        if self.banner_text ~= "任务中止 · 发动机关机" then
            self.banner_text = "任务中止 · 发动机关机"
            self.banner_tx:set_text(self.banner_text)
            self.banner:set_color(C.red, 44)
            self.banner_tx:set_color(C.red)
            self.banner:set_hidden(false)
        end
    elseif self.banner_text then
        self.banner_text = nil
        self.banner:set_hidden(true)
    end

    -- ---------- 遥测文字 ----------
    self.acc = self.acc + dt
    if self.acc >= conf.tick.text_ms / 1000 then
        self.acc = 0
        local alt = string.format("%.1f", st.alt)
        local vel = kit.fmt_num(st.vel)
        local acc = string.format("%.1f", st.acc)
        if alt ~= self.last_alt then self.last_alt = alt; self.vals[1]:set_text(alt) end
        if vel ~= self.last_vel then self.last_vel = vel; self.vals[2]:set_text(vel) end
        if acc ~= self.last_acc then self.last_acc = acc; self.vals[3]:set_text(acc) end
        local sub = "任务时间 " .. kit.fmt_ms(mission.clock()) ..
            "   ·   " .. (st.phase == "standby" and "待命待发" or "遥测正常")
        if sub ~= self.last_sub then self.last_sub = sub; self.sub:set_text(sub) end
    end
end

return M
