--[[
@module  ui_styles
@summary 音乐播放器 - 中间画面的 5 种风格
          唱片模式 / 歌词模式 / 柱状频谱 / 波形频谱 / 玻璃光波
@version 1.0
@date    2026.10.23
@note
除"歌词模式"的 7 行文字外，全部由 airui.shape 的 line/circle/arc/rect 图元实时绘制，
不依赖任何图片资源。

=== 关于"频谱数据从哪来" ===
Air8607 的音频链路上没有 PCM 出口：audio_v2 的回调只给
(request_index, event, param)，param 是驱动缓冲大小这类整数，没有数据指针；
exaudio 也没有 getData/getFrame 之类的接口，固件里也没有内置 VU/频谱组件。
真要真频谱只能自己解 mp3 再 audio_v2.stream 喂 PCM，而 Lua 侧没有 mp3 解码器。
所以这里用多路正弦叠加 + 节拍包络合成频谱，观感接近真实音乐频谱；
律动的时间轴只在"正在播放"时推进，暂停就定格在原地。

=== 暂停即定格 ===
调用方在暂停时传 dt = 0、t 不再增长，所以唱片角度、峰值帽、涟漪相位全部停住。
"暂停时唱片停止旋转 / 频谱停止律动"是自然结果，不需要额外状态变量。
]]

local fx = require "fx_core"
local theme = require "ui_theme"

local M = {}
local C = theme.C

--[[风格清单（UI 直接用它生成按钮文案，顺序即按钮顺序）]]
M.defs = {
    { id = "vinyl", name = "唱片模式", desc = "黑胶旋转 · 外圈进度环" },
    { id = "lyric", name = "歌词模式", desc = "逐行滚动 · 当前句高亮" },
    { id = "bars",  name = "柱状频谱", desc = "32 段律动 · 峰值帽倒影" },
    { id = "wave",  name = "波形频谱", desc = "三层波形 · 相位流动" },
    { id = "glass", name = "玻璃光波", desc = "光晕涟漪 · 镜面高光" },
}

--========================================================================
-- 公共
--========================================================================
local function new_shape(parent, W, H)
    local o = { w = W, h = H, pool = fx.pool() }
    o.shape = airui.shape({ parent = parent, x = 0, y = 0, w = W, h = H, items = {} })
    o.cx = math.floor(W / 2)
    o.cy = math.floor(H / 2)
    return o
end

--[[背景柔光：几层低透明度大圆叠出伪径向渐变
（填充椭圆在 C 层是逐行画线，代价高，所以只用 circle）
]]
local function ambient(o, P, hue, t, spread, base_opa)
    local cx, cy, W = o.cx, o.cy, o.w
    local pulse = 0.88 + 0.12 * math.sin(t * 1.9)
    for k = spread, 1, -1 do
        local r = math.floor(W * 0.085 * k * pulse)
        local opa = math.floor((base_opa or 12) * (spread - k + 1) / spread) + 8
        P:dot(cx, cy, r, fx.hsl(hue + k * 5 + t * 5, 0.8, 0.34), opa)
    end
end

--========================================================================
-- 1、唱片模式
--========================================================================
local function build_vinyl(parent, W, H)
    local o = new_shape(parent, W, H)
    o.r = math.floor(math.min(W, H) * 0.375)                 -- 盘面半径
    -- 唱臂：支点在右上角，针尖落在盘面内
    o.px = o.cx + o.r + math.floor(o.r * 0.34)
    o.py = o.cy - o.r - math.floor(o.r * 0.20)
    o.nx = o.cx + math.floor(o.r * 0.60)
    o.ny = o.cy - math.floor(o.r * 0.70)
    return o
end

local function update_vinyl(o, t, dt, info)
    local P = o.pool
    local cx, cy, R = o.cx, o.cy, o.r
    local rot = t * 48                       -- 度/秒：暂停时 t 不动，唱片就停住
    P:reset()

    -- 背后柔光
    ambient(o, P, 200, t, 6, 10)

    -- 盘面投影 + 盘面
    P:dot(cx + 4, cy + 9, R + 3, 0x02040A, 210)
    P:dot(cx, cy, R, 0x080D16, 255)
    P:ring(cx, cy, R, 0x28374F, 2, 255)

    -- 同心沟槽（静态纹理）
    for i = 1, 16 do
        local rr = R * (0.42 + 0.54 * i / 16)
        P:ring(cx, cy, rr, 0x1E2A42, 1, 105)
    end

    -- 旋转高光：两圈弧跟着 rot 走，这是"唱片在转"最直观的视觉线索
    local a0 = rot % 360
    for k = 0, 2 do
        local a = a0 + k * 120
        P:arc(cx, cy, math.floor(R * 0.90), a, a + 34, 0x4E86B8, 7, 85, true)
        P:arc(cx, cy, math.floor(R * 0.72), a + 48, a + 70, 0x2E5880, 5, 65, true)
    end

    -- 中心标签：三圈渐层 + 随唱片转的指针
    local lr = math.floor(R * 0.33)
    P:dot(cx, cy, lr, 0x111C2E, 255)
    P:ring(cx, cy, lr, 0x35507A, 2, 220)
    P:ring(cx, cy, math.floor(lr * 0.86), 0x22344F, 1, 180)
    local rad = math.rad(rot)
    local sx, sy = math.cos(rad), math.sin(rad)
    P:line(cx, cy, cx + sx * lr * 0.88, cy + sy * lr * 0.88, C.cyan, 4, 235, true)
    P:dot(cx + sx * lr * 0.56, cy + sy * lr * 0.56, 4, C.pink, 255)
    P:dot(cx - sx * lr * 0.56, cy - sy * lr * 0.56, 3, C.cyan, 150)

    -- 主轴
    P:dot(cx, cy, 5, 0xE8F2FF, 255)

    -- 唱臂（支点 + 臂杆 + 针头）
    P:line(o.px, o.py, o.nx, o.ny, 0xB8C6DA, 5, 225, true)
    P:dot(o.px, o.py, 9, 0x2C3F5E, 255)
    P:ring(o.px, o.py, 9, 0x7189A8, 2, 255)
    P:dot(o.px + 26, o.py - 6, 7, 0x40546F, 255)
    P:line(o.nx - 6, o.ny - 4, o.nx + 6, o.ny + 6, C.cyan, 3, 230, true)

    -- 外圈刻度 + 进度环（有总时长才画进度，否则只留底环）
    local pr = fx.clamp(info.progress or 0, 0, 1)
    local rr = R + 15
    for k = 0, 47 do
        local a = math.rad(k * 7.5 - 90)
        local r1 = rr + 4
        local r2 = r1 + ((k % 4 == 0) and 5 or 2)
        P:line(cx + math.cos(a) * r1, cy + math.sin(a) * r1,
               cx + math.cos(a) * r2, cy + math.sin(a) * r2,
               0x2A3B58, 1, (k % 4 == 0) and 200 or 110)
    end
    P:ring(cx, cy, rr, 0x1B2A44, 3, 255)
    if pr > 0.002 then
        local seg = 24
        for k = 0, seg - 1 do
            local p0 = k / seg
            if p0 <= pr then
                local p1 = math.min((k + 1) / seg, pr)
                P:arc(cx, cy, rr, -90 + p0 * 360, -90 + p1 * 360,
                      fx.hsl(186 + p0 * 60, 0.95, 0.58), 4, 245, false)
            end
        end
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

--========================================================================
-- 2、歌词模式
--========================================================================
local LSLOT = theme.layout.lyric_slots
local LLH = theme.layout.lyric_lh

local function build_lyric(parent, W, H)
    local o = new_shape(parent, W, H)
    o.labels = {}
    o.slot_line = {}       -- 每个槽位当前显示的行号，用于判断是否需要重新赋值
    o.pos = 1              -- 平滑后的当前行（浮点）
    o.cur = -1             -- 逻辑当前行
    o.lyric_ref = nil      -- 上一次用的歌词对象，切歌时用来重置槽位

    for j = 1, LSLOT do
        o.labels[j] = airui.label({
            parent = parent,
            x = 10, y = o.cy, w = W - 20, h = 40,
            text = "", font_size = theme.font.small, color = C.dim,
            align = airui.TEXT_ALIGN_CENTER,
        })
        o.slot_line[j] = -999
    end

    o.hint = airui.label({
        parent = parent, x = 10, y = o.cy - 40, w = W - 20, h = 34,
        text = "未找到歌词", font_size = theme.font.h2, color = C.dim2,
        align = airui.TEXT_ALIGN_CENTER,
    })
    o.hint2 = airui.label({
        parent = parent, x = 10, y = o.cy + 2, w = W - 20, h = 26,
        text = "把同名 .lrc 和歌曲放在一起", font_size = theme.font.tiny, color = C.dim2,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 上浮光点：位置固定，只按时间平移，暂停自然停住
    local rnd = fx.rng(20261023)
    o.ps = {}
    for i = 1, 22 do
        o.ps[i] = {
            x = rnd() * W,
            y = rnd() * H,
            r = 1 + math.floor(rnd() * 2),
            sp = 6 + rnd() * 16,
            ph = rnd() * 6.28,
            sw = 0.4 + rnd() * 0.9,
            a = 0.35 + rnd() * 0.65,
            h = 175 + rnd() * 90,
        }
    end
    return o
end

local function update_lyric(o, t, dt, info)
    local P = o.pool
    local W, H = o.w, o.h
    local cx, cy = o.cx, o.cy

    ---------------------------------------------------------------
    -- 一、背景层
    ---------------------------------------------------------------
    P:reset()
    ambient(o, P, 215, t, 5, 11)

    for i = 1, #o.ps do
        local p = o.ps[i]
        local y = (p.y - t * p.sp) % H
        if y < 0 then y = y + H end
        local x = p.x + math.sin(t * p.sw + p.ph) * 9
        local opa = math.floor((46 + 150 * p.a) * (0.55 + 0.45 * math.sin(t * 1.6 + p.ph)))
        if opa > 6 then
            P:dot(x, y, p.r, fx.hsl(p.h + t * 5, 0.75, 0.72), opa)
        end
    end

    -- 上下渐隐（用几条递增透明度的色带模拟遮罩，滚动时歌词不会硬生生"撞墙"）
    for k = 1, 7 do
        local opa = math.floor(200 * (1 - (k - 1) / 7))
        P:box(0, (k - 1) * 10, W, 10, C.bg2, opa, 0)
        P:box(0, H - k * 10, W, 10, C.bg2, opa, 0)
    end

    local ly = info.lyric
    local lines = ly and ly.lines or nil
    local n = lines and #lines or 0

    ---------------------------------------------------------------
    -- 二、歌词本体
    ---------------------------------------------------------------
    if n == 0 then
        -- 无歌词：清空文字槽位，只留柔光 + 提示文字
        for j = 1, LSLOT do
            if o.slot_line[j] ~= -999 then
                o.labels[j]:set_text("")
                o.slot_line[j] = -999
            end
        end
        o.lyric_ref = nil
        local s1 = ly and "歌词无法解析" or "未找到歌词"
        local s2 = ly and "请检查文件里的时间戳" or "把同名 .lrc 和歌曲放在一起"
        if o.hint_text ~= s1 then
            o.hint:set_text(s1)
            o.hint_text = s1
        end
        if o.hint2_text ~= s2 then
            o.hint2:set_text(s2)
            o.hint2_text = s2
        end
        o.n = P:finish()
        o.shape:set_items(P.items)
        return
    end

    -- 切歌后重置槽位缓存，避免整屏文字错位
    if o.lyric_ref ~= ly then
        o.lyric_ref = ly
        o.cur = -1
        o.pos = 1
        for j = 1, LSLOT do o.slot_line[j] = -999 end
        if o.hint_text ~= "" then o.hint:set_text(""); o.hint_text = "" end
        if o.hint2_text ~= "" then o.hint2:set_text(""); o.hint2_text = "" end
    end

    -- 当前行：从上次位置向后推进（也支持切歌/跳播时回退）
    local ms = info.pos_ms or 0
    local idx = o.cur
    if idx < 0 then idx = 1 end
    if idx > n then idx = n end
    while idx < n and lines[idx + 1].t <= ms + 100 do idx = idx + 1 end
    while idx > 1 and lines[idx].t > ms + 100 do idx = idx - 1 end
    o.cur = idx

    -- 平滑滚动：目标就是当前行号，跨太多行（切歌）时直接吸附
    local target = idx
    if math.abs(target - o.pos) > 3 then
        o.pos = target
    elseif dt > 0 then
        o.pos = fx.approach(o.pos, target, dt * 6.5)
        if math.abs(target - o.pos) < 0.004 then o.pos = target end
    end

    local base = math.floor(o.pos + 0.5)
    local frac = o.pos - base

    -- 高亮药丸 + 当前句的卡拉OK进度条
    local y_act = cy - frac * LLH
    P:box(cx - math.floor((W - 60) / 2), y_act - 21, W - 60, 42,
          fx.mix(C.cyan, C.violet, 0.5), 26, 21)
    P:box(cx - math.floor((W - 60) / 2), y_act - 21, 4, 42, C.cyan, 150, 2)

    local l0 = lines[base]
    if l0 then
        local span = math.max(1, (l0.e or (l0.t + 1200)) - l0.t)
        local pp = fx.clamp((ms - l0.t) / span, 0, 1)
        local bw = math.floor((W - 120) * pp)
        if bw > 3 then
            P:box(cx - math.floor((W - 120) / 2), y_act + 23, bw, 3, C.cyan, 210, 2)
        end
    end

    ---------------------------------------------------------------
    -- 三、7 个文字槽位
    ---------------------------------------------------------------
    for j = 1, LSLOT do
        local d = j - (math.floor(LSLOT / 2) + 1)     -- -3..3
        local li = base + d
        local y = cy + (d - frac) * LLH - 20

        local lbl = o.labels[j]
        if o.slot_line[j] ~= li then
            o.slot_line[j] = li
            if li >= 1 and li <= n then
                --[[字号只分 3 档（22 / 17 / 15）
                hzfont 的字形缓存按 (字符, 字号) 计数，档位越多滚一遍歌词要栅格化的次数越多；
                远近关系主要靠颜色表达，字号只做两级收缩就够看了。]]
                local fs = (d == 0) and 22 or ((math.abs(d) == 1) and 17 or 15)
                lbl:set_text(fx.fit(lines[li].s, W - 44, fs))
                lbl:set_font_size(fs)
                if d == 0 then
                    lbl:set_color(C.text)
                elseif math.abs(d) == 1 then
                    lbl:set_color(0xA9BBD8)
                elseif math.abs(d) == 2 then
                    lbl:set_color(0x7086A8)
                else
                    lbl:set_color(0x4B5A78)
                end
            else
                lbl:set_text("")
            end
        end
        lbl:set_pos(10, math.floor(y))
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

--========================================================================
-- 3、柱状频谱
--========================================================================
local NB = 32                  -- 频段数
local BPAD = 20                -- 左右留白
local FALL = 0.62              -- 峰值帽下落速度（每秒）

local function build_bars(parent, W, H)
    local o = new_shape(parent, W, H)
    o.peak, o.val = {}, {}
    o.ci, o.si = {}, {}
    for i = 1, NB do
        o.peak[i], o.val[i] = 0.05, 0.05
        -- 预计算空间分量：4 个 sin(t*w ± i*k) 按和角公式展开，每帧只剩 8 次三角函数
        o.ci[i] = { math.cos(i * 0.62), math.cos(i * 0.95), math.cos(i * 0.23), math.cos(i) }
        o.si[i] = { math.sin(i * 0.62), math.sin(i * 0.95), math.sin(i * 0.23), math.sin(i) }
    end
    return o
end

local function update_bars(o, t, dt, info)
    local P = o.pool
    local W, H = o.w, o.h
    P:reset()

    ambient(o, P, 190, t, 4, 9)

    local bw = math.floor((W - BPAD * 2) / NB)
    local base = math.floor(H * 0.66)
    local maxh = math.floor(H * 0.48)
    local beat = 0.70 + 0.30 * math.sin(t * 3.6)

    local s1, c1 = math.sin(t * 3.3), math.cos(t * 3.3)
    local s2, c2 = math.sin(t * 5.1), math.cos(t * 5.1)
    local s3, c3 = math.sin(t * 1.6), math.cos(t * 1.6)
    local s4, c4 = math.sin(t * 7.3), math.cos(t * 7.3)

    for i = 1, NB do
        local f = (i - 1) / (NB - 1)
        local ci, si = o.ci[i], o.si[i]
        local v = (0.5 + 0.5 * (s1 * ci[1] + c1 * si[1])) * 0.55
                + (0.5 + 0.5 * (s2 * ci[2] - c2 * si[2])) * 0.28
                + (0.5 + 0.5 * (s3 * ci[3] + c3 * si[3])) * 0.17
        v = v * (1 - f * 0.45) * beat
        v = v * (0.84 + 0.16 * (0.5 + 0.5 * (s4 * ci[4] + c4 * si[4])))
        v = fx.clamp(v, 0.05, 1)

        if v > o.peak[i] then
            o.peak[i] = v
        elseif dt > 0 then
            o.peak[i] = o.peak[i] - dt * FALL
            if o.peak[i] < v then o.peak[i] = v end
        end
        o.val[i] = v

        local x = BPAD + (i - 1) * bw
        local iw = math.max(3, bw - 3)
        local h = math.max(4, math.floor(v * maxh))
        local col = fx.hsl(186 + f * 130 + t * 10, 0.92, 0.38 + 0.26 * v)

        P:box(x + 1, base - h, iw, h, col, 255, 3)                     -- 柱体
        P:box(x + 1, base + 5, iw, math.floor(h * 0.30), col, 55, 3)   -- 倒影
        local py = base - math.max(5, math.floor(o.peak[i] * maxh)) - 6
        P:box(x + 1, py, iw, 3, 0xFFFFFF, 205, 1)                      -- 峰值帽
    end

    -- 基线 + 一条随节拍扫过的光带
    P:line(BPAD, base + 3, W - BPAD, base + 3, 0x2A4A6B, 2, 255, true)
    P:line(BPAD, base + 3, W - BPAD, base + 3, C.cyan, 1, 55, true)
    local sweep = (t * 0.28) % 1
    local sx = BPAD + (W - BPAD * 2) * sweep
    P:box(sx - 22, base - maxh - 8, 44, maxh + 12, C.cyan, 12, 14)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

--========================================================================
-- 4、波形频谱
--========================================================================
local NSEG = 46               -- 折线段数

local function build_wave(parent, W, H)
    local o = new_shape(parent, W, H)
    o.amp = math.floor(H * 0.26)
    return o
end

local function update_wave(o, t, dt, info)
    local P = o.pool
    local W, H = o.w, o.h
    local C2 = C
    P:reset()

    ambient(o, P, 200, t, 4, 8)

    local left = BPAD
    local right = W - BPAD
    local step = (right - left) / NSEG
    local cy = o.cy + 4

    -- 网格 + 中轴线
    for k = 0, 8 do
        local x = left + (right - left) * k / 8
        P:line(x, cy - o.amp * 1.35, x, cy + o.amp * 1.35, 0x16253C, 1, 150)
    end
    for k = -2, 2 do
        if k ~= 0 then
            local y = cy + k * o.amp * 0.55
            P:line(left, y, right, y, 0x152238, 1, 90)
        end
    end
    P:dash(left, cy, right, cy, 0x22375A, 1, 255, 8, 8)

    -- 三层波形：主波 + 相位偏移的陪衬波 + 低频包络
    local p1, p2, p3 = t * 2.1, t * 3.7, t * 1.15
    local px1, py1 = left, cy
    local px2, py2 = left, cy
    local px3, py3 = left, cy

    for k = 0, NSEG do
        local f = k / NSEG
        local u = left + step * k
        local env = math.sin(f * math.pi)     -- 两端收敛，避免"撞墙"
        local a = (math.sin(f * 9.0 + p1) * 0.55
                + math.sin(f * 17.0 - p2) * 0.28
                + math.sin(f * 4.0 + p3) * 0.17) * env
        local y1 = cy - a * o.amp
        local y2 = cy - a * o.amp * 0.55
        local y3 = cy + math.sin(f * 6.0 - p2 * 0.7) * env * o.amp * 0.32

        if k > 0 then
            P:line(px1, py1, u, y1, fx.hsl(186 + f * 120 + t * 12, 0.95, 0.60), 3, 245, true)
            P:line(px2, py2, u, y2, fx.hsl(268 + f * 80 + t * 9, 0.90, 0.60), 2, 120, true)
            P:line(px3, py3, u, y3, fx.hsl(320 + f * 40 - t * 10, 0.85, 0.60), 1, 80, true)
        end
        px1, py1 = u, y1
        px2, py2 = u, y2
        px3, py3 = u, y3
    end

    -- 播放位置光点（跟随进度沿中轴移动，进度未知时停在左侧）
    local pr = fx.clamp(info.progress or 0, 0, 1)
    local mx = left + (right - left) * pr
    P:line(mx, cy - o.amp * 1.4, mx, cy + o.amp * 1.4, C2.cyan, 1, 60)
    P:dot(mx, cy, 4, C2.cyan, 255)
    P:ring(mx, cy, 9, C2.cyan, 1, 120)

    o.n = P:finish()
    o.shape:set_items(P.items)
end

--========================================================================
-- 5、玻璃光波
--========================================================================
local function build_glass(parent, W, H)
    local o = new_shape(parent, W, H)
    o.r = math.floor(math.min(W, H) * 0.40)
    local rnd = fx.rng(861023)
    o.ps = {}
    for i = 1, 16 do
        o.ps[i] = {
            a = rnd() * 6.28,
            rr = 0.35 + rnd() * 0.95,
            sp = 0.12 + rnd() * 0.34,
            ph = rnd() * 6.28,
            r = 1 + math.floor(rnd() * 2),
        }
    end
    return o
end

local function update_glass(o, t, dt, info)
    local P = o.pool
    local cx, cy, R = o.cx, o.cy, o.r
    P:reset()

    -- 中心光晕：多层半透明实心圆叠加出伪渐变
    local pulse = 0.86 + 0.14 * math.sin(t * 2.6)
    for k = 6, 1, -1 do
        local rr = math.floor(R * (0.14 + k * 0.135) * pulse)
        local hue = 198 - k * 7 + t * 8
        P:dot(cx, cy, rr, fx.hsl(hue, 0.9, 0.34), 15 + k * 3)
    end
    P:dot(cx, cy, math.floor(R * 0.10), 0xEAF6FF, 235)

    -- 涟漪：4 圈向外扩散，越外越淡，暂停时相位不动
    for k = 0, 3 do
        local phase = (t * 0.32 + k * 0.25) % 1
        local rr = math.floor(R * 0.16 + phase * R * 1.05)
        local opa = math.floor(((1 - phase) ^ 2) * 205)
        if opa > 6 then
            local hue = 190 + phase * 95 + t * 6
            P:ring(cx, cy, rr, fx.hsl(hue, 0.85, 0.62), 3, opa)
            P:ring(cx, cy, rr - 7, fx.hsl(hue, 0.85, 0.74), 1, math.floor(opa * 0.5))
        end
    end

    -- 旋转镜面高光（玻璃质感）
    local a0 = (t * 30) % 360
    P:arc(cx, cy, math.floor(R * 0.94), a0, a0 + 66, 0xFFFFFF, 2, 70, true)
    P:arc(cx, cy, math.floor(R * 0.94), a0 + 180, a0 + 222, 0xBEE8FF, 2, 38, true)

    -- 环绕光点（椭圆轨道，制造 3D 悬浮感）
    for i = 1, #o.ps do
        local p = o.ps[i]
        local a = p.a + t * p.sp
        local x = cx + math.cos(a) * R * p.rr
        local y = cy + math.sin(a) * R * p.rr * 0.52
        local opa = math.floor(70 + 150 * (0.5 + 0.5 * math.sin(t * p.sp * 6 + p.ph)))
        P:dot(x, y, p.r, fx.hsl(190 + p.rr * 70 + t * 10, 0.9, 0.78), opa)
    end

    -- 底部进度光带
    local pr = fx.clamp(info.progress or 0, 0, 1)
    local bw = math.floor(R * 1.75)
    local bx = cx - math.floor(bw / 2)
    local by = cy + math.floor(R * 1.06)
    P:box(bx, by, bw, 4, 0x14243C, 255, 2)
    if pr > 0.002 then
        P:box(bx, by, math.max(3, math.floor(bw * pr)), 4, C.cyan, 255, 2)
        P:dot(bx + math.floor(bw * pr), by + 2, 4, 0xFFFFFF, 220)
    end

    o.n = P:finish()
    o.shape:set_items(P.items)
end

--========================================================================
-- 统一入口
--========================================================================
local BUILD = {
    vinyl = build_vinyl,
    lyric = build_lyric,
    bars  = build_bars,
    wave  = build_wave,
    glass = build_glass,
}
local UPDATE = {
    vinyl = update_vinyl,
    lyric = update_lyric,
    bars  = update_bars,
    wave  = update_wave,
    glass = update_glass,
}

--[[创建一个风格实例
@param string kind vinyl/lyric/bars/wave/glass
@param userdata parent 父容器
@param number W,H 画布宽高
@return table obj
]]
function M.build(kind, parent, W, H)
    local b = BUILD[kind]
    if not b then return nil end
    local o = b(parent, W, H)
    o.kind = kind
    o.n = 0
    return o
end

--[[逐帧更新
@param table o build 返回的对象
@param number t 视觉时间（秒，只有播放时增长）
@param number dt 本帧步长（秒，暂停时传 0）
@param table info { playing=, progress=0..1, pos_ms=, lyric=, lyric_src= }
]]
function M.update(o, t, dt, info)
    local u = UPDATE[o.kind]
    if u then u(o, t, dt, info) end
end

return M
