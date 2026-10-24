--[[
@module  ui
@summary BEAT FORGE - 界面（网格 / 反应堆 / 示波器 / 控制条 / 触摸 / 主循环）
@version 1.0
@date    2026.10.22
@author  江访
@usage
五层画布，动静分离：
  shBg      静态层，开机画一次：底色 / 卡片 / 暗格 / 刻度
  shGrid    30fps：点亮的步进格 + 播放头扫光 + 静音行压暗
  shReactor 30fps：节拍反应堆（刻度圈 / 8 轨 VU 辐条 / 脉冲环 / 涟漪）
  shCtl     30fps：PAT 芯片 + 控制按钮（按下有闪光反馈）
  shScope   20fps：真实输出 PCM 波形 + 8 轨电平柱

关键取舍：暗格画在静态层、亮格画在动态层。
点格子只改图案数据，下一帧动态层自然跟上，不用做任何图元失效管理；
动态层平时只有"亮着的格子"在画，默认图案约 34 格，图元预算稳定。

触摸走 airui.touch_subscribe 全局订阅 + 自建命中测试（同 moto_dash），
原生 airui.slider 在顶栏自己收触摸，两边互不抢。
]]

local T = require "theme"
local E = require "engine"
local fx = require "fx"

local airui = airui
local M = {}

local C = T.c
local F = T.f
local st = E.st
local NT = #T.tracks

-- 触摸常量按 C 层枚举兜底（moto_dash 同款）：个别固件不导出 TP_*，
-- 直接比 nil 会让整个界面点不动。AIRUI_TOUCH_STATE_DOWN = 1
local TP_DOWN = airui.TP_DOWN or 1

-- 时间基准（engine 同款换算，UI 独立一份，互不干扰）
local TICKS_PER_MS = 1

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    return os.time() * 1000
end

local function tick_diff(a, b)
    local d = a - b
    if d < -2147483648 then d = d + 4294967296 end
    return d
end

-- ==================== 几何（全部由 theme 推导）====================
local SW, SH = T.screen.w, T.screen.h
local G = T.grid
local CELL_X0 = G.x + G.label_w + 8        -- 步进格起点 x = 424
local CELL_PITCH = G.cell_w + G.gap         -- 36
local GRID_H = G.rows * G.row_h             -- 288
local R = T.reactor
local S = T.scope
local PCH = T.pat
local BOT = T.bottom
local BUTTON_Y = BOT.y + 12                 -- 按钮条 y = 524
local BUTTON_H = 48

-- 按钮矩形 {名称, x, w}
local BUTTONS = {
    { id = "PLAY",  x = 36,  w = 128 },
    { id = "STOP",  x = 176, w = 128 },
    { id = "FILL",  x = 316, w = 128 },
    { id = "CLEAR", x = 456, w = 128 },
}

-- 顶栏滑块 {key, x, w, 颜色}
local SLIDERS = {
    { key = "bpm",   x = 300, w = 180, color = C.cyan },
    { key = "swing", x = 576, w = 150, color = C.lime },
    { key = "vol",   x = 820, w = 130, color = C.magenta },
}
local SLIDER_Y = 28

-- ==================== 运行状态 ====================
local o = {
    root = nil,
    shBg = nil, shGrid = nil, shReactor = nil, shCtl = nil, shScope = nil,
    lbTrack = {},        -- 8 个轨名 label
    lbChip = {},         -- 4 个 PAT label
    lbBtn = {},          -- 4 个按钮 label
    spin = 0,            -- 反应堆自转角
    rip = {},            -- 涟漪 {x, y, r, life, color}
    flash = {},          -- 按钮闪光 {id = 0..1}
    ctl_dirty = true,    -- 控制层脏标记：按钮/芯片平时不变，不逐帧重建
    -- 图元池
    pBg = nil, pGrid = nil, pReactor = nil, pCtl = nil, pScope = nil,
    nGrid = 0, nReactor = 0, nCtl = 0, nScope = 0,
}

local function lbl(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h, text = text,
        font_size = size, color = color,
        align = align or airui.TEXT_ALIGN_LEFT,
    })
end

-- 涟漪：触摸反馈，扩一圈就散
local function ripple(x, y, color)
    local n = #o.rip
    if n >= 8 then return end
    o.rip[n + 1] = { x = x, y = y, r = 6, life = 1, color = color }
end

-- ==================== 构建整屏 ====================
local function build_static()
    local P = o.pBg
    P:reset()
    -- 底色与顶栏 / 底栏
    P:box(0, 0, SW, SH, C.bg, 255, 0)
    P:box(0, 0, SW, T.hud.h, 0x0A0D16, 255, 0)
    P:line(0, T.hud.h, SW, T.hud.h, C.line, 1, 255)
    P:box(0, BOT.y, SW, SH - BOT.y, 0x0A0D16, 255, 0)
    P:line(0, BOT.y, SW, BOT.y, C.line, 1, 255)

    -- 网格卡 / 示波器卡
    P:box(G.x - 8, G.y - 8, G.label_w + 8 + G.cols * CELL_PITCH + 8, GRID_H + 16,
        C.panel, 255, 12)
    P:box(S.x - 8, S.y - 8, S.w + 16, S.h + 16, C.panel, 255, 12)

    -- 128 个暗格：静态层画一次，点亮交给动态层
    for r = 1, G.rows do
        local cy = G.y + (r - 1) * G.row_h + 5
        for s = 1, G.cols do
            local cx = CELL_X0 + (s - 1) * CELL_PITCH
            P:frame(cx, cy, G.cell_w, G.cell_h, C.dim2, 1, 150, 4)
        end
    end
    -- 每 4 步一个拍点刻度（1/5/9/13 步上面一颗亮钉）
    for s = 1, G.cols, 4 do
        local cx = CELL_X0 + (s - 1) * CELL_PITCH + G.cell_w / 2
        P:dot(cx, G.y - 2, 2, C.line2, 255)
    end
    -- 反应堆底圈
    P:ring(R.cx, R.cy, R.R, C.line, 1, 255)
    local n = P:finish()
    o.shBg:set_items(P.items)
    log.info("beat", "静态层图元", n)
end

function M.build()
    o.root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    -- 动态层先建（压在卡片之下），文本最后建（浮在最上）
    o.shBg      = airui.shape({ parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {} })
    o.shGrid    = airui.shape({ parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {} })
    o.shReactor = airui.shape({ parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {} })
    o.shCtl     = airui.shape({ parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {} })
    o.shScope   = airui.shape({ parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {} })

    o.pBg      = fx.pool()
    o.pGrid    = fx.pool()
    o.pReactor = fx.pool()
    o.pCtl     = fx.pool()
    o.pScope   = fx.pool()

    build_static()

    -- ==================== 顶栏 ====================
    lbl(o.root, 24, 8, 260, 38, "BEATFORGE", F.big, C.cyan)
    lbl(o.root, 24, 44, 280, 16, "节拍熔炉 STEP SEQUENCER", F.mini, C.dim)
    lbl(o.root, 300, 8, 80, 14, "BPM", F.mini, C.dim)
    lbl(o.root, 576, 8, 80, 14, "SWING", F.mini, C.dim)
    lbl(o.root, 820, 8, 80, 14, "VOL", F.mini, C.dim)
    o.lbBpmV   = lbl(o.root, 488, 12, 70, 28, "124", F.val, C.cyan)
    o.lbSwingV = lbl(o.root, 734, 12, 80, 28, "0%", F.val, C.lime)
    o.lbVolV   = lbl(o.root, 958, 12, 60, 28, "70", F.val, C.magenta)

    -- 原生滑块：参数旋钮，样式跟配色走（回调只带自身，用 get_value 回读）
    for _, s in ipairs(SLIDERS) do
        local min, max, val
        if s.key == "bpm" then
            min, max, val = T.audio.bpm_min, T.audio.bpm_max, st.bpm
        elseif s.key == "swing" then
            min, max, val = 0, 30, math.floor(st.swing * 100 + 0.5)
        else
            min, max, val = 0, 100, st.vol
        end
        airui.slider({
            parent = o.root, x = s.x, y = SLIDER_Y, w = s.w, h = 20,
            min = min, max = max, value = val,
            style = {
                bg_color = 0x1A2233, bg_opa = 255,
                radius = 10, pad = 0,
                indicator_color = s.color,
                knob_color = 0xEDF2FF,
            },
            on_change = function(obj)
                local ok, v = pcall(function() return obj:get_value() end)
                if not ok or type(v) ~= "number" then return end
                if s.key == "bpm" then
                    E.set_bpm(v)
                elseif s.key == "swing" then
                    E.set_swing(v / 100)
                else
                    E.set_vol(v)
                end
            end,
        })
    end

    -- ==================== 轨名 / 反应堆中心 ====================
    for r = 1, NT do
        local y = G.y + (r - 1) * G.row_h + 7
        o.lbTrack[r] = lbl(o.root, G.x, y, G.label_w - 4, 22,
            T.tracks[r].name, F.body, T.tracks[r].color)
    end
    o.lbBpmBig = lbl(o.root, R.cx - 90, R.cy - 46, 180, 74,
        tostring(st.bpm), F.huge, C.txt, airui.TEXT_ALIGN_CENTER)
    o.lbRSub = lbl(o.root, R.cx - 90, R.cy + 26, 180, 18,
        "BPM / STOP", F.sub, C.dim, airui.TEXT_ALIGN_CENTER)

    -- ==================== PAT 芯片 + 按钮文本 ====================
    for i = 1, 4 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x = PCH.x + col * (PCH.w + PCH.gap)
        local y = PCH.y + row * (PCH.h + PCH.gap)
        o.lbChip[i] = lbl(o.root, x, y + 12, PCH.w, 26,
            "PAT " .. T.pat_order[i], F.val, C.dim, airui.TEXT_ALIGN_CENTER)
    end
    for _, b in ipairs(BUTTONS) do
        o.lbBtn[b.id] = lbl(o.root, b.x, BUTTON_Y + 12, b.w, 26,
            b.id, F.val, C.txt, airui.TEXT_ALIGN_CENTER)
    end

    -- ==================== 底栏提示 / 状态 ====================
    lbl(o.root, 600, BOT.y + 10, 410, 22,
        "点格子编曲 / 点轨名静音 / 点反应堆打鼓", F.body, C.dim)
    o.lbStatus = lbl(o.root, 600, BOT.y + 42, 410, 18, "", F.sub, C.dim2)

    log.info("beat", "界面构建完成")
end

-- ==================== 触摸路由（自建命中测试）====================
local function on_touch(state, x, y)
    if state ~= TP_DOWN then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    o.ctl_dirty = true

    -- 1、步进格：点一下翻转，点亮的同时出声（编曲即演奏）
    if x >= CELL_X0 and y >= G.y and y < G.y + GRID_H then
        local s = math.floor((x - CELL_X0) / CELL_PITCH) + 1
        local r = math.floor((y - G.y) / G.row_h) + 1
        if s >= 1 and s <= G.cols and r >= 1 and r <= G.rows then
            if E.toggle_step(r, s) == 1 then E.hit(r) end
            ripple(x, y, C.cyan)
            return
        end
    end

    -- 2、轨名列：点一下静音 / 解除
    if x >= G.x and x < CELL_X0 and y >= G.y and y < G.y + GRID_H then
        local r = math.floor((y - G.y) / G.row_h) + 1
        if r >= 1 and r <= G.rows then
            local muted = E.toggle_mute(r)
            o.lbTrack[r]:set_color(muted and C.dim2 or T.tracks[r].color)
            ripple(x, y, T.tracks[r].color)
            return
        end
    end

    -- 3、PAT 芯片
    for i = 1, 4 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local px = PCH.x + col * (PCH.w + PCH.gap)
        local py = PCH.y + row * (PCH.h + PCH.gap)
        if x >= px and x < px + PCH.w and y >= py and y < py + PCH.h then
            E.set_pat(T.pat_order[i])
            ripple(x, y, C.violet)
            return
        end
    end

    -- 4、控制按钮
    if y >= BUTTON_Y and y < BUTTON_Y + BUTTON_H then
        for _, b in ipairs(BUTTONS) do
            if x >= b.x and x < b.x + b.w then
                if b.id == "PLAY" then
                    E.play()
                elseif b.id == "STOP" then
                    E.stop()
                elseif b.id == "FILL" then
                    E.fill()
                    E.hit(2)          -- 加花配一声军鼓，即时反馈
                else
                    E.clear()
                end
                o.flash[b.id] = 1
                ripple(x, y, C.cyan)
                return
            end
        end
    end

    -- 5、反应堆：当打击垫，一拳一个底鼓
    local dx, dy = x - R.cx, y - R.cy
    if dx * dx + dy * dy <= R.R * R.R then
        E.hit(1)
        ripple(x, y, C.magenta)
    end
end

-- ==================== 动态绘制 ====================
-- 网格：亮格 + 播放头 + 静音行压暗（30fps）
local function draw_grid()
    local P = o.pGrid
    P:reset()
    local p = st.pat

    -- 播放头：一根青色光带扫过当前列，宽窄随步内进度呼吸
    if st.playing then
        local step, frac = E.playhead()
        local px = CELL_X0 + step * CELL_PITCH + G.cell_w / 2
        P:box(px - 1, G.y - 4, 2, GRID_H + 8, C.cyan, 70 + math.floor(120 * frac), 1)
        P:dot(px, G.y - 2, 3 + math.floor(frac * 2), C.cyan, 230)
    end

    -- 点亮的格子：轨道色实心块 + 内芯，响的那一行跟着包络变亮
    for r = 1, G.rows do
        local cy = G.y + (r - 1) * G.row_h + 5
        local env = st.env[r] or 0
        local muted = st.mute[r]
        local col = muted and C.dim2 or T.tracks[r].color
        for s = 1, G.cols do
            if p[r][s] == 1 then
                local cx = CELL_X0 + (s - 1) * CELL_PITCH
                local opa = muted and 110 or (150 + math.floor(105 * env))
                P:box(cx, cy, G.cell_w, G.cell_h, col, opa, 4)
                P:box(cx + 4, cy + 4, G.cell_w - 8, G.cell_h - 8,
                    fx.shade(col, 0.5), math.floor(opa * 0.8), 3)
            end
        end
    end

    -- 节拍高亮：每拍把顶边横线刷一层品红脉冲
    if st.pulse > 0.02 then
        local a = math.floor(120 * st.pulse)
        P:line(G.x, G.y - 6, CELL_X0 + G.cols * CELL_PITCH, G.y - 6, C.magenta, 2, a)
    end
    o.nGrid = P:finish()
    o.shGrid:set_items(P.items)
end

-- 反应堆：刻度圈自转 + 8 轨 VU 辐条 + 脉冲环 + 涟漪（30fps）
local function draw_reactor(dt)
    local P = o.pReactor
    P:reset()
    local cx, cy = R.cx, R.cy
    local pulse = st.pulse

    -- 外圈 24 根刻度，随 spin 旋转；落在当前拍上的那根最亮
    local seg = 24
    for i = 1, seg do
        local a = o.spin + (i - 1) / seg * fx.TAU
        local ca, sa = math.cos(a), math.sin(a)
        local long = ((i - 1) % 6 == 0)
        local len = long and 16 or 8
        local opa = long and (140 + math.floor(100 * pulse)) or 90
        local col = long and C.cyan or C.line2
        P:line(cx + ca * (R.R - len), cy + sa * (R.R - len),
            cx + ca * (R.R - 2), cy + sa * (R.R - 2), col, 2, opa, true)
    end

    -- 8 轨 VU 辐条：包络实时往外顶，颜色即轨道色
    for r = 1, NT do
        local a = -math.pi / 2 + (r - 1) / NT * fx.TAU
        local ca, sa = math.cos(a), math.sin(a)
        local env = st.env[r] or 0
        local inner = R.R - 30
        local outer = inner + 12 + env * 34
        local col = st.mute[r] and C.dim2 or T.tracks[r].color
        P:line(cx + ca * inner, cy + sa * inner, cx + ca * outer, cy + sa * outer,
            col, 5, 90 + math.floor(150 * env), true)
    end

    -- 双脉冲环：拍一到就往外鼓一下
    P:ring(cx, cy, 58 + pulse * 9, C.cyan, 1, 120 + math.floor(110 * pulse))
    P:ring(cx, cy, 82 + pulse * 5, C.magenta, 2, 70 + math.floor(120 * pulse))

    -- 中心准星
    P:line(cx - 12, cy, cx - 5, cy, C.line2, 2, 200)
    P:line(cx + 5, cy, cx + 12, cy, C.line2, 2, 200)
    P:dot(cx, cy, 2, C.cyan, 220)

    -- 涟漪：触摸反馈，扩一圈就散
    for i = #o.rip, 1, -1 do
        local g = o.rip[i]
        g.r = g.r + dt * 260
        g.life = g.life - dt * 1.6
        if g.life <= 0 then
            table.remove(o.rip, i)
        else
            P:ring(g.x, g.y, math.floor(g.r), g.color, 2, math.floor(130 * g.life))
        end
    end

    o.nReactor = P:finish()
    o.shReactor:set_items(P.items)
end

-- 控制层：PAT 芯片 + 按钮（30fps，按下闪光）
local function draw_ctl(dt)
    local P = o.pCtl
    P:reset()
    for i = 1, 4 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x = PCH.x + col * (PCH.w + PCH.gap)
        local y = PCH.y + row * (PCH.h + PCH.gap)
        local active = (st.pat_id == T.pat_order[i])
        P:box(x, y, PCH.w, PCH.h, active and C.panel_hl or C.panel, 255, 10)
        P:frame(x, y, PCH.w, PCH.h, active and C.violet or C.line, active and 2 or 1,
            active and 255 or 160, 10)
    end
    for _, b in ipairs(BUTTONS) do
        local f = o.flash[b.id] or 0
        if f > 0 then
            f = f - dt * 3
            if f < 0 then f = 0 end
            o.flash[b.id] = f
        end
        local is_play = (b.id == "PLAY" and st.playing)
        local base = (b.id == "PLAY" or b.id == "STOP") and C.panel_hl or C.panel
        P:box(b.x, BUTTON_Y, b.w, BUTTON_H, base, 255, 10)
        P:frame(b.x, BUTTON_Y, b.w, BUTTON_H,
            is_play and C.cyan or C.line2, is_play and 2 or 1,
            is_play and 255 or (140 + math.floor(115 * f)), 10)
    end
    o.nCtl = P:finish()
    o.shCtl:set_items(P.items)
end

-- 示波器：真实输出 PCM 波形 + 8 轨电平柱（20fps）
local wv = {}
local function draw_scope()
    local P = o.pScope
    P:reset()
    local n = st.wave_n
    for i = 1, n do
        wv[i] = (st.wave[i] + 1) * 0.5
    end
    -- 波形两层：品红宽底光 + 青色细芯，一条 poly 一个图元，便宜
    P:line(S.x + 16, S.y + 46, S.x + 480, S.y + 46, C.line2, 1, 120)
    fx.spark(P, wv, n, S.x + 16, S.y + 4, 464, 84, C.magenta, 6, 70)
    fx.spark(P, wv, n, S.x + 16, S.y + 4, 464, 84, C.cyan, 2, 235)

    -- 输出总电平
    local sum = 0
    for i = 1, n do
        local v = st.wave[i]
        sum = sum + (v < 0 and -v or v)
    end
    fx.meter(P, S.x + 500, S.y + 8, 164, 8, sum / n * 1.6, C.cyan)

    -- 8 轨电平柱：底部起跳，颜色即轨道色，静音压灰
    for r = 1, NT do
        local x = S.x + 500 + (r - 1) * 21
        local y0 = S.y + 26
        local h = 62
        local env = st.env[r] or 0
        local col = st.mute[r] and C.dim2 or T.tracks[r].color
        P:frame(x, y0, 18, h, C.line, 1, 150, 3)
        local fh = env * (h - 4)
        if fh >= 2 then
            P:box(x + 2, y0 + h - 2 - fh, 14, fh, col, 230, 2)
        end
    end
    o.nScope = P:finish()
    o.shScope:set_items(P.items)
end

-- HUD 文本（4Hz，变字才 set_text，不逐帧刷）
local hudTxt = {}
local function set_txt(lb, key, s)
    if hudTxt[key] ~= s then
        hudTxt[key] = s
        lb:set_text(s)
    end
end

local function update_hud()
    set_txt(o.lbBpmV, "bv", tostring(st.bpm))
    set_txt(o.lbSwingV, "sv", math.floor(st.swing * 100 + 0.5) .. "%")
    set_txt(o.lbVolV, "vv", tostring(st.vol))
    set_txt(o.lbBpmBig, "bb", tostring(st.bpm))
    set_txt(o.lbRSub, "rs", "BPM / " .. (st.playing and "PLAY" or "STOP"))
    for i = 1, 4 do
        o.lbChip[i]:set_color(st.pat_id == T.pat_order[i] and C.txt or C.dim)
    end
    local dbg = airui.debug()
    local fps = (type(dbg) == "table" and dbg.fps) or 0
    set_txt(o.lbStatus, "st", string.format(
        "PAT %s  %s  FPS %d  图元 %d",
        st.pat_id, st.silent and "SILENT" or "AUDIO",
        math.floor(fps + 0.5), o.nGrid + o.nReactor + o.nCtl + o.nScope))
end

-- ==================== 主循环（30fps，节拍补偿）====================
function M.run()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then TICKS_PER_MS = hz / 1000 end
    airui.touch_subscribe(on_touch)
    log.info("beat", "主循环启动")

    local last = now_ms()
    local scopeT, hudT = 1000, 1000
    while true do
        local t0 = now_ms()
        local dt = tick_diff(t0, last) / TICKS_PER_MS / 1000
        last = t0
        if dt > 0.25 then dt = 0.25 elseif dt <= 0 then dt = 0.03 end

        -- 衰减：脉冲快收，包络慢收（鼓声余韵和视觉余韵匹配）
        st.pulse = st.pulse - dt * 2.2
        if st.pulse < 0 then st.pulse = 0 end
        for r = 1, NT do
            local e = st.env[r] - dt * 3.2
            st.env[r] = (e < 0) and 0 or e
        end
        o.spin = o.spin + dt * (0.5 + st.pulse * 3.5)

        draw_grid()
        draw_reactor(dt)
        -- 控制层只在被按下或闪光衰减时重绘：省掉一层全屏图元的
        -- 每帧重建，真机 airui 刷新队列不再积压
        local flashing = false
        for _, v in pairs(o.flash) do
            if v > 0 then flashing = true break end
        end
        if o.ctl_dirty or flashing then
            draw_ctl(dt)
            o.ctl_dirty = false
        end

        scopeT = scopeT + dt * 1000
        if scopeT >= T.perf.scope_ms then
            scopeT = 0
            draw_scope()
        end

        hudT = hudT + dt * 1000
        if hudT >= T.perf.hud_ms then
            hudT = 0
            update_hud()
        end

        -- 等待扣掉本轮耗时：固定 30ms 节拍，不累加漂移（moto_dash 同款）
        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS
        local w = T.perf.frame_ms - cost
        if w < 5 then w = 5 end
        sys.wait(w)
    end
end

return M
