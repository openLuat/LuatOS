--[[
@module  scene
@summary 天空场景：日夜渐变 / 星星 / 云 / 远山草地 / 雨雪粒子，并把角色层叠进去
@version 1.0
@date    2026.11.08

=== 分两层，是为了帧率 ===
sky 层（静态）：天空渐变 60 条、地面、远山 —— 只在配色变化时重画（约 1 分钟一次）。
fx  层（动态，10fps）：星星、云、草地/树/石子（随地面滚动）、雨雪粒子、小窝与角色。
两者都是铺满全屏的 airui.shape；fx 在 sky 之上，背景透明，所以天空能透出来。

=== 地面什么时候动 ===
骑行模式（cyclist）：角色钉在屏幕中间踩车，**地面后退** 147px/秒 —— 与车轮周长×转速对齐，
  草、树、石子一起后退，看起来就是"一直在往前骑"。
小动物模式（cat/dog）：地面完全静止（草、树、远山、小窝都不动），只有小动物走来走去。
  反过来做的话，房子会跟着地面一起平移 —— 一件不会动的建筑在漂移，一眼假。

=== 日夜怎么算 ===
按小时取关键帧（SKY）做线性插值，daylight 因子控制地面亮度与星星透明度。
关键帧只改一处：SKY 表。想换配色不用动任何绘制代码。
]]

local draw = require "draw"
local actor = require "actor"
local conf = require "conf"

local M = {}

M.HORIZON = 470          -- 地平线（也是角色站立的地面线）

local W, H = conf.W, conf.H

local sky_shape, fx_shape
local P_sky, P_fx
local last_sky = { top = -1, ground = -1 }

-- ==================== 天空关键帧 ====================
-- { 小时, 顶部, 中部, 地平线 }
local SKY = {
    { 0.0,  0x081226, 0x0E1C36, 0x18304E },
    { 4.5,  0x081226, 0x0E1C36, 0x18304E },
    { 5.6,  0x0B1533, 0x1E2C55, 0x3D4166 },
    { 6.6,  0x1B2A5C, 0x5B4C7A, 0xE08B5A },
    { 8.0,  0x2A6FB0, 0x6FA9D8, 0xCFE6F5 },
    { 12.0, 0x2E7BC4, 0x8FC3E8, 0xD8EEF8 },
    { 16.0, 0x2A6FB0, 0x7FB4DE, 0xF0DCC0 },
    { 18.0, 0x3C2A5E, 0x8C5A72, 0xF0955A },
    { 19.4, 0x1B2148, 0x3A3358, 0x7A4F63 },
    { 21.0, 0x0C1730, 0x13233E, 0x1E3350 },
    { 24.0, 0x081226, 0x0E1C36, 0x18304E },
}

local GROUND_DAY   = 0x2E8C8C
local GROUND_NIGHT = 0x0B2B35

local function sky_key(h)
    local a = SKY[1]
    local b = SKY[#SKY]
    for i = 1, #SKY - 1 do
        if h >= SKY[i][1] and h <= SKY[i + 1][1] then
            a, b = SKY[i], SKY[i + 1]
            break
        end
    end
    local span = (b[1] - a[1])
    local t = span > 0 and draw.clamp((h - a[1]) / span, 0, 1) or 0
    return draw.mix(a[2], b[2], t), draw.mix(a[3], b[3], t), draw.mix(a[4], b[4], t)
end

local function daylight_at(h)
    if h >= 8 and h <= 17 then return 1 end
    if h < 6 or h > 19.5 then return 0 end
    if h < 8 then return (h - 6) / 2 end
    return (19.5 - h) / 2.5
end

-- ==================== 环境 ====================

--- 由时间 + 天气算出本帧的环境参数
---@param now table time_util.now() 的返回值
---@param wx table|nil 当前天气（可能为 nil）
function M.env(now, wx)
    local h = now.hour_f or 12
    --[[量化到 5 分钟：小时连续变化会让插值出的颜色每一帧都不一样，
    静态天空就会变成"每帧都重画"，白白多渲染一整屏。]]
    local hq = math.floor(h * 12 + 0.5) / 12
    local top, mid, hor = sky_key(hq)
    local dl = daylight_at(hq)

    local e = {
        hour = h,
        daylight = dl,
        night = (h >= conf.time.night_start) or (h < conf.time.night_end),
        sky_top = top,
        sky_mid = mid,
        sky_horizon = hor,
        ground = draw.mix(GROUND_NIGHT, GROUND_DAY, dl),
        ground_y = M.HORIZON,
    }
    e.ground_dark = draw.shade(e.ground, -0.45)
    e.ground_light = draw.shade(e.ground, 0.18)
    e.star_opa = math.floor((1 - dl) * 232)

    local cond = (wx and wx.condition) or "晴"
    e.condition = cond
    e.is_rain = (cond == "雨")
    e.is_snow = (cond == "雪")
    return e
end

-- ==================== 静态层：天空 / 地面 / 远山 ====================

local function draw_sky(e)
    local P = P_sky
    P:reset()

    -- 渐变：分 60 条，顶部 → 中部 → 地平线
    -- 条数少（原来 30 条）在 10 寸屏上能看出横向色带，60 条每档 8px 基本看不出来
    local bands = 60
    local band_h = math.ceil(M.HORIZON / bands)
    for i = 0, bands - 1 do
        local t = (i + 0.5) / bands
        local c
        if t < 0.55 then
            c = draw.mix(e.sky_top, e.sky_mid, t / 0.55)
        else
            c = draw.mix(e.sky_mid, e.sky_horizon, (t - 0.55) / 0.45)
        end
        P:box(0, i * band_h, W, band_h + 1, c, 255)
    end

    --[[远山：地平线后的一排实心椭圆，山脊只露出地平线以上一小截
    先画山、再画地面 —— 地面矩形会把椭圆的下半截盖掉，剩下的正好是远处的山脊。
    顺序反过来就是一大坨深色椭圆糊在地上（踩过的坑）。]]
    local hills = {
        { x = 40,  r = 96,  k = 1.0 }, { x = 210, r = 74, k = 0.8 },
        { x = 400, r = 110, k = 1.1 }, { x = 600, r = 80,  k = 0.9 },
        { x = 800, r = 104, k = 1.0 }, { x = 990, r = 86,  k = 0.85 },
    }
    local hill_c = draw.shade(e.ground, -0.20)
    for _, hl in ipairs(hills) do
        P:ellipse(hl.x, M.HORIZON + hl.r * 0.34, hl.r, hl.r * 0.62 * hl.k, hill_c, 0, 0, true, 255)
    end

    -- 地面（盖住远山下半截）
    P:box(0, M.HORIZON, W, H - M.HORIZON, e.ground, 255)
    P:line(0, M.HORIZON, W, M.HORIZON, e.ground_light, 2, 255)

    -- 草和树在动态层：骑行时要跟着地面一起后退（见文件头）
    P:finish()
    sky_shape:set_items(P.items)
    last_sky.top = e.sky_top
    last_sky.ground = e.ground
end

-- ==================== 动态层素材 ====================

local stars = {}
do
    local rnd = draw.rng(4711)
    for i = 1, 26 do
        stars[i] = {
            x = math.floor(rnd() * W),
            y = math.floor(rnd() * (M.HORIZON - 120)),
            r = (rnd() < 0.18) and 2 or 1,
            ph = rnd() * math.pi * 2,
        }
    end
end

--[[云：y 必须让整朵云的顶端落在 130 以下
云顶 = y - 6*s - 28*s（见 draw_cloud）。原来第一朵 y=96、s=2.1，云顶算出来是 25 ——
正好糊在左上角的时间日期上，白字压白云，日期直接看不见了。现在最低一朵云顶 145。
]]
local clouds = {
    { x = 30,   y = 215, s = 1.9, v = 7 },
    { x = 470,  y = 168, s = 1.1, v = 12 },
    { x = 760,  y = 258, s = 0.9, v = 17 },
}

local marks = {}
do
    local rnd = draw.rng(91)
    for i = 1, 10 do
        marks[i] = { x = rnd() * W, y = M.HORIZON + 12 + rnd() * 92, len = 8 + rnd() * 16 }
    end
end

--[[地面装饰：草簇 + 树
骑行时跟地面一起后退（速度 = 车轮线速度），小动物模式下整片地面静止。
所有装饰按 LOOP_SPAN 取模循环，位置固定（固定种子），不会越跑越少。
]]
local LOOP_SPAN = W + 260
local ground_off = 0    -- 地面已滚过的距离（px），只有骑行模式会累加

local decos = {}
do
    local rnd = draw.rng(20261108)
    local x = 20
    for i = 1, 12 do
        x = x + 62 + rnd() * 52
        decos[#decos + 1] = {
            kind = "grass", x = x,
            h = 7 + rnd() * 13,
            lean = (rnd() - 0.5) * 10,
        }
    end
    -- 树的 x 手动挑开，避免全挤在一起
    local tree = {
        { x = 150, h = 54, r = 25 },
        { x = 430, h = 68, r = 30 },
        { x = 690, h = 50, r = 23 },
        { x = 940, h = 62, r = 27 },
    }
    for i = 1, #tree do
        decos[#decos + 1] = {
            kind = "tree", x = tree[i].x, h = tree[i].h, r = tree[i].r,
        }
    end
end

local particles = {}
local p_mode = "none"

local function init_particles(mode)
    p_mode = mode
    particles = {}
    local rnd = draw.rng(313)
    local n = (mode == "rain") and 40 or 32
    for i = 1, n do
        particles[i] = {
            x = rnd() * W,
            y = rnd() * (M.HORIZON - 20),
            v = (mode == "rain") and (380 + rnd() * 240) or (36 + rnd() * 44),
            sway = rnd() * math.pi * 2,
            -- 雨丝长度按速度给：10fps 下每帧位移 38~62px，长度够长才连得起来
            len = (mode == "rain") and (18 + rnd() * 12) or 3,
        }
    end
end

local T = 0     -- 全局时间（ms），给摆动/闪烁用

-- ==================== 动态层绘制 ====================

local function draw_stars(P, e)
    if e.star_opa < 10 then return end
    for i = 1, #stars do
        local s = stars[i]
        local tw = 0.55 + 0.45 * math.sin(T / 900 + s.ph)
        local opa = math.floor(e.star_opa * tw)
        if opa > 6 then
            P:dot(s.x, s.y, s.r, 0xFFF6D8, opa)
        end
    end
end

local function draw_cloud(P, cx, cy, s, color, opa)
    P:ellipse(cx, cy + 10 * s, 58 * s, 20 * s, color, 0, 0, true, opa)
    P:ellipse(cx - 30 * s, cy + 3 * s, 28 * s, 22 * s, color, 0, 0, true, opa)
    P:ellipse(cx + 2 * s, cy - 6 * s, 32 * s, 28 * s, color, 0, 0, true, opa)
    P:ellipse(cx + 34 * s, cy + 5 * s, 24 * s, 18 * s, color, 0, 0, true, opa)
end

local function draw_clouds(P, e, dt_s)
    local base = draw.mix(0x50668C, 0xF4F9FF, e.daylight)
    if e.is_rain or e.is_snow then base = draw.mix(base, 0x9FB0C4, 0.65) end
    local opa = math.floor(120 + 80 * e.daylight)
    for i = 1, #clouds do
        local c = clouds[i]
        c.x = c.x + c.v * dt_s
        if c.x > W + 160 * c.s then c.x = -180 * c.s end
        draw_cloud(P, c.x, c.y, c.s, base, opa)
    end
end

--- 地面装饰（草簇 + 树）：位置 = 固定 x - 已滚距离，按 LOOP_SPAN 循环
local function draw_deco(P, e)
    local gy = M.HORIZON
    local grass_c = draw.shade(e.ground, -0.50)
    local trunk_c = draw.shade(e.ground, -0.62)
    local leaf_c  = draw.shade(e.ground, -0.36)
    local leaf_c2 = draw.shade(e.ground, -0.24)

    for i = 1, #decos do
        local d = decos[i]
        local x = (d.x - ground_off) % LOOP_SPAN
        if x < W + 130 then
            if d.kind == "grass" then
                P:line(x, gy + 3, x + d.lean, gy + 3 - d.h, grass_c, 2, 235)
                P:line(x + 4, gy + 5, x + 6 + d.lean, gy + 8 - d.h * 0.7, grass_c, 2, 185)
            else
                -- 树：树干 1 + 树冠 4，一棵 5 个图元（没有多边形填充，用圆叠）
                P:box(x - 4, gy + 2 - d.h, 9, d.h, trunk_c, 255, 3)
                P:dot(x, gy - d.h - d.r * 0.55, d.r, leaf_c, 255)
                P:dot(x - d.r * 0.78, gy - d.h + d.r * 0.10, d.r * 0.72, leaf_c, 255)
                P:dot(x + d.r * 0.78, gy - d.h + d.r * 0.16, d.r * 0.68, leaf_c, 255)
                P:dot(x - d.r * 0.18, gy - d.h - d.r * 0.30, d.r * 0.52, leaf_c2, 210)
            end
        end
    end
end

local function draw_marks(P, e)
    local c = draw.shade(e.ground, -0.30)
    for i = 1, #marks do
        local m = marks[i]
        local x = (m.x - ground_off) % LOOP_SPAN
        if x < W + 30 then
            P:line(x, m.y, x + m.len, m.y, c, 2, 130)
            if i % 3 == 0 then
                P:dot(x + m.len + 6, m.y + 2, 2, c, 110)
            end
        end
    end
end

local function draw_particles(P, e, dt_s)
    if p_mode == "none" then return end
    for i = 1, #particles do
        local p = particles[i]
        if p_mode == "rain" then
            p.y = p.y + p.v * dt_s
            p.x = p.x - 70 * dt_s
            if p.y > M.HORIZON - 6 then
                p.y = -20 - (i % 7) * 12
                p.x = (p.x + 173) % W
            end
            if p.x < -6 then p.x = W + 6 end
            P:line(p.x, p.y, p.x - 2, p.y + p.len, 0xC7DDF2, 2, 120)
        else
            p.y = p.y + p.v * dt_s
            p.x = p.x + math.sin(T / 700 + p.sway) * 14 * dt_s
            if p.y > M.HORIZON - 6 then
                p.y = -10
                p.x = (p.x + 97) % W
            end
            P:dot(p.x, p.y, (i % 5 == 0) and 3 or 2, 0xFFFFFF, 190)
        end
    end
end

-- ==================== 对外接口 ====================

--- 建场景（必须在 HUD / 预报页之前调用：LVGL 后创建的对象在上面）
function M.build(parent)
    P_sky = draw.pool()
    P_fx = draw.pool()

    sky_shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H })
    fx_shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H })
    return sky_shape, fx_shape
end

--- 每帧调用：需要时重画静态天空
function M.update_sky(e)
    if e.sky_top ~= last_sky.top or e.ground ~= last_sky.ground then
        draw_sky(e)
    end
end

--- 每帧调用：重画动态层（云/草地树木/雨雪/角色）
---@param dt number 距上一帧的毫秒数
---@param e table 环境
---@param a table 角色状态（actor.new 的返回值）
function M.tick(dt, e, a)
    if not fx_shape then return end
    local dt_s = math.min(dt, 400) / 1000
    T = T + dt

    --[[只有骑行模式地面才后退；小动物模式下地面（草/树/石子/远山）一动不动，
    房子才不会跟着"漂移"。速度 147px/秒 与车轮线速度对齐，见 actor.update。]]
    local scrolling = (a and a.kind == "cyclist")
    if scrolling then
        ground_off = (ground_off + 147 * dt_s) % LOOP_SPAN
    end

    -- 雨雪模式切换时重建粒子
    local mode = e.is_rain and "rain" or (e.is_snow and "snow" or "none")
    if mode ~= p_mode then init_particles(mode) end

    local P = P_fx
    P:reset()

    -- 阴雨天压暗整片天空（fx 在 sky 之上，一层半透明就够了）
    if e.is_rain or e.is_snow then
        P:box(0, 0, W, M.HORIZON, 0x0A1826, 38)
    end

    draw_stars(P, e)
    draw_clouds(P, e, dt_s)
    draw_deco(P, e)
    draw_marks(P, e)
    draw_particles(P, e, dt_s)
    actor.draw(P, a, e)

    P:finish()
    fx_shape:set_items(P.items)
end

return M
