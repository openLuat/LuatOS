--[[
@module page_music
@summary 音乐播放器 HMI：顶栏 / 左导航 / 四屏（播放·曲库·收藏·设置）/ 迷你条 / toast
         移植 8603_music/index.html（1024×600，day/night 双主题）

=== 结构 ===
单个 exwin 页，屏内四块【预建容器】+ set_hidden 切换（踩坑：destroy+重建会留残影）。
  scr_play / scr_lib / scr_fav / scr_set 一次性建好，切页只改可见性 + 刷文本。
  nav / 顶栏 / 迷你条 / toast 挂 root，创建顺序在屏之后（层级更高、不被屏拦触摸）。

=== 刷新 ===
只起一个 sys.taskInit 循环（禁用 timerLoopStart）：
  100ms 一帧：频谱 2 个 shape（共 40 根柱）各 set_items 一次；
  1000ms：推进播放时间、刷时间读数。
  所有 set_items 走 put()：空图元且已清空 → 直接 return（空表也会标脏、打爆堆）。
]]

local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"
local ok_audio, app_audio = pcall(require, "app_audio")
if not ok_audio then app_audio = nil end

local M = {}
local S, P = mock.S, mock.P
local W, H = theme.W, theme.H
local C              -- = theme.C，每次 build 重新取
local R              -- 运行期句柄表，每次 build 重建

local TOP_H  = 48
local NAV_W  = 76
local MINI_H = 56
local MINI_Y = H - MINI_H
local PX, PY = 24, 20          -- 主区内边距（相对屏容器）

--------------------------------------------------------------------
-- 构造期小工具
--------------------------------------------------------------------
local drawn, tstr = {}, {}

-- 空图元且已清过 → 跳过（set_items 无条件 invalidate，空表会把整块标脏）
local function put(sh, items)
    if not sh then return end
    local has = items and #items > 0
    if not has and not drawn[sh] then return end
    drawn[sh] = has or nil
    pcall(sh.set_items, sh, items or {})
end

-- nil-safe 方法调用：先取方法再 pcall，避免对象为 nil 时在 pcall 外索引报错
local function call(obj, method, ...)
    if not obj then return false end
    local f = obj[method]
    if type(f) ~= "function" then return false end
    return pcall(f, obj, ...)
end

-- 可见页立即刷新，其余页延后一帧，避免一次点击产生几十次 set_items
local function refresh_all()
    if P.page == "play" then M.refresh_play()
    elseif P.page == "library" then M.refresh_lib()
    elseif P.page == "favorites" then M.refresh_fav() end
    M.refresh_mini()
    theme.defer(function()
        if P.page ~= "play" then M.refresh_play() end
        if P.page ~= "library" then M.refresh_lib() end
        if P.page ~= "favorites" then M.refresh_fav() end
    end)
end

-- 表格里只显示格式第一段（html 的 x.fmt.split(' ')[0]）
local function fmt_short(s)
    s = tostring(s or "")
    local f = string.find(s, " ·", 1, true)
    return f and string.sub(s, 1, f - 1) or s
end

local function set_text(lb, s)
    if not lb or s == nil then return end
    if tstr[lb] == s then return end
    tstr[lb] = s
    pcall(lb.set_text, lb, s)
end

local function set_hidden(o, hide)
    if o and o.set_hidden then pcall(o.set_hidden, o, not not hide) end
end

local function txt(parent, x, y, w, h, s, col, size, align)
    return theme.txt(parent, x, y, w, h, s, col, size, align)
end

-- 按码点截断（封面/胶囊里的专辑名会超宽，直接截比让它裁掉半个字好看）
local function short_ch(s, n)
    s = tostring(s or "")
    local out, c = {}, 0
    for _, ch in utf8.codes(s) do
        if c >= n then
            out[#out + 1] = "…"
            break
        end
        out[#out + 1] = utf8.char(ch)
        c = c + 1
    end
    return table.concat(out)
end

local AL, AC, AR = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT
local function ln(x1, y1, x2, y2, col, w)
    return { type = "line", x1 = math.floor(x1), y1 = math.floor(y1),
             x2 = math.floor(x2), y2 = math.floor(y2), color = col, width = w or 1,
             round_start = true, round_end = true }
end
local function rc(x, y, w, h, col, r)
    return { type = "rect", x = math.floor(x), y = math.floor(y),
             w = math.floor(w), h = math.floor(h), radius = r or 0, color = col,
             width = 1, fill = true, fill_color = col, fill_opacity = 255 }
end
local function cl(cx, cy, r, col, opa)
    return { type = "circle", cx = math.floor(cx), cy = math.floor(cy),
             r = math.floor(r), color = col, width = 1,
             fill = true, fill_color = col, fill_opacity = opa or 255 }
end

-- 空心圆（外环），对应 html 的 stroke-only circle
local function ri(cx, cy, r, col, wd, opa)
    return { type = "circle", cx = math.floor(cx), cy = math.floor(cy),
             r = math.floor(r), color = col, width = wd or 1,
             fill = false, fill_color = col, fill_opacity = opa or 0 }
end

-- 背景网格线：按现场要求完全去掉，保留空函数避免改动各屏构建顺序
local function build_grid(parent, ox, oy, w, h)
end

--------------------------------------------------------------------
-- 顶栏：brand + 副标题 + 音源 + 图标 + 时钟 + 主题按钮
--------------------------------------------------------------------
local function build_top(root)
    local bar = theme.box(root, 0, 0, W, TOP_H, C.bg)
    build_grid(bar, 0, 0, W, TOP_H)
    theme.box(bar, 0, TOP_H - 1, W, 1, C.line)

    txt(bar, 24, 12, 80, 24, "AUDIO", C.text, 16, AL)
    theme.box(bar, 104, 14, 1, 20, C.line2)
    local sub = txt(bar, 116, 12, 300, 24, mock.PAGES[1].name, C.dim, 16, AL)

    R.source_dot = theme.circle(bar, 588, 21, 5, C.ac)
    R.source = txt(bar, 600, 12, 180, 24, "SD CARD · 本地曲库", C.sub, 16, AL)

    R.bt_ic = theme.icon(bar, 800, 14, 20, 20, airui.SYMBOL_BLUETOOTH, C.dim, 18)
    R.wifi_ic = theme.icon(bar, 830, 12, 24, 24, airui.SYMBOL_WIFI, C.dim, 22)

    R.clock = txt(bar, 856, 12, 64, 24, "00:00", C.text, 16, AR)

    local tb = airui.container({ parent = bar, x = 928, y = 7, w = 40, h = 34,
        color = C.btn, radius = 8, border_color = C.line2, border_width = 1 })
    theme.register(tb, function() return C.btn end)
    theme.register(tb, function() return C.line2 end, nil, true)
    R.theme_mark = theme.shape(tb, (theme.mode == "day") and 13 or 25,
        10, 2, 14)
    put(R.theme_mark, { rc(0, 0, 2, 14, C.dim, 1) })
    R.theme_lb = txt(bar, 970, 12, 54, 24, (theme.mode == "day") and "白天" or "夜间",
        C.dim, 16, AL)
    theme.hit(bar, 928, 7, 40, 34, function() M.toggle_theme() end)

    R.hd_sub = sub
    return bar, sub
end

--------------------------------------------------------------------
-- 左侧导航：四个按钮（每个图标都是 shape）
--------------------------------------------------------------------
local function nav_items(idx, active)
    local col = active and C.ac or C.dim
    if idx == 1 then return theme.IC.note(21, 21, col) end
    if idx == 2 then
        local it = {}
        for k = 0, 2 do
            it[#it + 1] = cl(3, 4 + k * 6, 1, col)
            it[#it + 1] = ln(7, 4 + k * 6, 18, 4 + k * 6, col, 2)
        end
        return it
    end
    if idx == 3 then return theme.IC.heart(21, 21, col, false) end
    return theme.IC.gear(21, 21, col)
end

local function nav_symbol(i)
    if i == 1 then return airui.SYMBOL_AUDIO end
    if i == 2 then return airui.SYMBOL_LIST end
    return airui.SYMBOL_SETTINGS
end

local function build_nav(root)
    local nav = theme.box(root, 0, TOP_H, NAV_W, H - TOP_H, C.nav)
    build_grid(nav, 0, TOP_H, NAV_W, H - TOP_H)
    theme.box(nav, NAV_W - 1, 0, 1, H - TOP_H, C.line)
    R.nav_btn, R.nav_ic = {}, {}
    for i = 1, 4 do
        local y = 20 + (i - 1) * 56
        local active = (P.page == mock.PAGES[i].id)
        local btn = airui.container({ parent = nav, x = 14, y = y, w = 48, h = 48,
            color = active and C.acw or C.nav, radius = 10,
            border_color = active and C.acline or C.line, border_width = 1 })
        R.nav_btn[i] = btn
        if i == 3 then
            local sh = theme.shape(btn, 14, 14, 21, 21)
            put(sh, theme.IC.heart(21, 21, active and C.ac or C.sub, false))
            R.nav_ic[i] = sh
        else
            R.nav_ic[i] = theme.icon(btn, 14, 14, 21, 21,
                nav_symbol(i), active and C.ac or C.sub, 20)
        end
        theme.hit(nav, 14, y, 48, 48, function() M.goto_page(mock.PAGES[i].id) end)
    end
    R.nav_idx = txt(nav, 0, H - TOP_H - 38, NAV_W, 20, "01 / 04", C.dim, 16, AC)
    return nav
end

--------------------------------------------------------------------
-- 播放屏（scr_play）
--------------------------------------------------------------------
-- 封面：按 html 的 art 分支画 8 套构图（只 line/circle/rect，单 shape ≤32 图元）
local function cover_items(tr)
    local band = theme.mix(0x0B1216, tr.g2, 0.52)   -- html: rect y286 opacity .52
    local it = {}
    for k = 0, 7 do
        it[#it + 1] = rc(0, k * 38, 300, 38,
            theme.mix(tr.g1, tr.g2, k / 7), 0)
    end
    it[#it + 1] = rc(0, 215, 300, 85, band, 0)
    local art = tr.art or "simple"

    if art == "sun" then
        local sun = theme.mix(0xFFF4D2, tr.g1, 0.08)
        local cloud = theme.mix(0xFFFFFF, tr.g1, 0.38)
        local wave = theme.mix(0x5E8CA6, tr.g1, 0.38)
        it[#it + 1] = ri(219, 84, 63, cloud, 2)
        it[#it + 1] = cl(219, 84, 42, sun)
        it[#it + 1] = cl(40, 104, 11, cloud)
        it[#it + 1] = cl(62, 99, 14, cloud)
        it[#it + 1] = cl(86, 104, 9, cloud)
        it[#it + 1] = rc(29, 104, 78, 12, cloud, 6)
        for k = 0, 3 do
            local y = 165 + k * 16
            it[#it + 1] = ln(0, y + 4, 150, y - 2, wave, 1)
            it[#it + 1] = ln(150, y - 2, 300, y + 6, wave, 1)
        end

    elseif art == "tornado" then
        local c = theme.mix(0xBBD0D2, tr.g1, 0.25)
        for k = 0, 7 do
            local cx = 150 + math.floor(math.sin(k * 0.85) * 22)
            local cy = 116 + k * 11
            it[#it + 1] = ri(cx, cy, 22 + k * 8, c, 2)
        end
        for k = 0, 3 do
            it[#it + 1] = ln(118 + k * 18, 78, 132 + k * 14, 212,
                theme.mix(0xFFFFFF, c, 0.45), 1)
        end

    elseif art == "summer" then
        it[#it + 1] = cl(231, 95, 36, theme.mix(0xF6E4B4, tr.g1, 0.15))
        local w = theme.mix(0x6E8B5E, tr.g1, 0.38)
        for k = 0, 8 do
            local y = 165 + k * 15
            it[#it + 1] = ln(0, y + 5, 150, y - 3, w, 1)
            it[#it + 1] = ln(150, y - 3, 300, y + 7, w, 1)
        end
        local bird = theme.mix(0x4A5A44, tr.g1, 0.45)
        it[#it + 1] = ln(72, 72, 86, 66, bird, 2)
        it[#it + 1] = ln(86, 66, 101, 72, bird, 2)
        it[#it + 1] = ln(114, 56, 123, 51, bird, 1)
        it[#it + 1] = ln(123, 51, 132, 56, bird, 1)

    elseif art == "rice" then
        local stem = theme.mix(0xF4E0A4, tr.g1, 0.38)
        local grain = theme.mix(0xF0D896, tr.g1, 0.48)
        for k = 0, 7 do
            local x = 14 + k * 36
            local y = 158 + (k % 3) * 10
            it[#it + 1] = ln(x, 220, x + 5, y, stem, 2)
            it[#it + 1] = cl(x + 5, y + 7, 4, grain)
        end
        it[#it + 1] = ln(0, 218, 300, 218, theme.mix(0xFFF0C0, tr.g2, 0.24), 1)

    elseif art == "nocturne" then
        it[#it + 1] = cl(219, 78, 34, theme.mix(0xE8ECF4, tr.g1, 0.12))
        it[#it + 1] = cl(204, 66, 33, theme.mix(0x22304C, tr.g1, 0.08))
        local star = theme.mix(0xFFFFFF, tr.g1, 0.4)
        local pts = { { 40, 47 }, { 76, 87 }, { 111, 39 }, { 147, 72 },
                      { 256, 44 }, { 274, 107 }, { 57, 134 }, { 178, 51 },
                      { 214, 142 }, { 32, 168 } }
        for k = 1, #pts do it[#it + 1] = cl(pts[k][1], pts[k][2], 2, star) end
        local w = theme.mix(0x9FB2D4, tr.g1, 0.5)
        for k = 0, 5 do it[#it + 1] = ln(0, 180 + k * 12, 300, 184 + k * 12, w, 1) end

    elseif art == "porcelain" then
        local c = theme.mix(0x3C6C96, tr.g1, 0.45)
        it[#it + 1] = ri(150, 125, 84, c, 2)
        it[#it + 1] = ri(150, 125, 66, c, 2)
        it[#it + 1] = cl(150, 125, 32, theme.mix(0x3C6C96, tr.g1, 0.7))
        for k = 0, 7 do
            local a = math.rad(k * 45)
            local x = math.floor(150 + math.cos(a) * 55)
            local y = math.floor(125 + math.sin(a) * 55)
            it[#it + 1] = cl(x, y, 13, theme.mix(0x3C6C96, tr.g1, 0.54))
        end
        it[#it + 1] = ln(0, 197, 300, 197, theme.mix(0x3C6C96, tr.g2, 0.28), 1)

    elseif art == "balloon" then
        local bl = { { 65, 112, 26 }, { 126, 84, 33 }, { 197, 118, 28 },
                     { 245, 78, 21 }, { 159, 156, 20 } }
        for k = 1, #bl do
            local q = bl[k]
            it[#it + 1] = cl(q[1], q[2], q[3], theme.mix(tr.c1, tr.g1, 0.22))
            it[#it + 1] = cl(q[1] - math.floor(q[3] * 0.3),
                q[2] - math.floor(q[3] * 0.4), math.max(3, math.floor(q[3] * 0.22)),
                theme.mix(0xFFFFFF, tr.g1, 0.35))
            it[#it + 1] = ln(q[1], q[2] + q[3], q[1] - 3, 215,
                theme.mix(0x8B7A72, tr.g1, 0.55), 1)
        end

    else
        local moon = theme.mix(0xFFFFFF, tr.g1, 0.30)
        it[#it + 1] = ri(219, 84, 63, moon, 2)
        it[#it + 1] = cl(219, 84, 42, moon)
        it[#it + 1] = ln(0, 170, 300, 110, theme.mix(0x5E93A8, tr.g1, 0.30), 14)
        it[#it + 1] = ln(0, 202, 300, 142, theme.mix(0x3E7488, tr.g1, 0.44), 12)
        it[#it + 1] = ln(0, 226, 300, 166, theme.mix(0x2E6E86, tr.g1, 0.56), 10)
        for k = 0, 4 do it[#it + 1] = cl(35 + k * 51, 63 + (k % 2) * 18, 4,
            theme.mix(0xFFFFFF, tr.g1, 0.45)) end
    end
    return it
end

local function build_play(root)
    local scr = theme.box(root, NAV_W, TOP_H, W - NAV_W, H - TOP_H, C.bg)
    R.scr_play = scr
    build_grid(scr, NAV_W, TOP_H, W - NAV_W, H - TOP_H)

    -- 左栏
    txt(scr, PX, PY, 240, 20, "NOW PLAYING", C.dim, 16, AL)
    R.p_idx = txt(scr, PX, PY, 368, 20, "01 / 08", C.dim, 16, AR)

    theme.box_b(scr, PX, PY + 28, 300, 300, C.card2, 10, C.line, 1)
    R.cover = theme.shape(scr, PX, PY + 28, 300, 300)
    R.cv_album = txt(scr, PX + 20, PY + 46, 220, 20, "", C.cover_txt, 16, AL)
    R.cv_name = txt(scr, PX + 20, PY + 238, 168, 30, "", C.cover_txt, 24, AL)
    R.cv_en = txt(scr, PX + 20, PY + 270, 260, 18, "", C.cover_txt, 16, AL)
    R.cv_no = txt(scr, PX + 192, PY + 238, 92, 20, "", C.cover_txt, 16, AR)
    R.cover_fade = airui.container({ parent = scr, x = PX + 1, y = PY + 29,
        w = 298, h = 298, color = C.bg2, radius = 10 })
    pcall(R.cover_fade.set_color, R.cover_fade, C.bg2, 0)

    R.p_name = txt(scr, PX, PY + 336, 368, 34, "", C.text, 27, AL)
    R.p_artist = txt(scr, PX, PY + 372, 368, 22, "", C.sub, 16, AL)

    -- 四枚标签：与 html 一样每行两枚（格式+ALBUM / 主题+音源状态）
    local tagw = { 260, 96, 150, 200 }
    local tagx = { PX, PX + 268, PX, PX + 158 }
    local tagy = { PY + 396, PY + 396, PY + 428, PY + 428 }
    local tg = {}
    for i = 1, 4 do
        local hl = (i == 1 or i == 4)
        theme.box_b(scr, tagx[i], tagy[i], tagw[i], 28, hl and C.acw or C.panel2,
            6, hl and C.acline or C.line, 1)
        tg[i] = txt(scr, tagx[i], tagy[i] + 1, tagw[i], 26, "",
            hl and C.ac or C.sub, 18, AC)
    end
    R.p_tag = tg

    -- 频谱卡
    local sc = theme.box_b(scr, 416, 20, 508, 76, C.card, 12, C.line, 1)
    txt(sc, 14, 8, 300, 20, "SPECTRUM / 频谱", C.dim, 16, AL)
    R.sp_state = txt(sc, 314, 8, 180, 20, "20Hz - 20kHz", C.dim, 16, AR)
    R.spec_a = theme.shape(sc, 14, 32, 237, 38)
    R.spec_b = theme.shape(sc, 254, 32, 240, 38)

    return scr
end

local function build_prog(scr)
    local pc = theme.box_b(scr, 416, 107, 508, 86, C.card, 12, C.line, 1)
    R.p_cur = txt(pc, 14, 8, 120, 22, "00:00", C.text, 16, AL)
    R.p_dur = txt(pc, 394, 8, 100, 22, "00:00", C.sub, 16, AR)
    theme.box(pc, 14, 38, 480, 6, C.track, 3)
    R.p_fill = theme.shape(pc, 14, 38, 480, 6)
    R.p_knob = theme.circle(pc, 14, 35, 12, C.ac)
    R.p_meta = txt(pc, 14, 54, 340, 20, "", C.dim, 16, AL)
    R.p_pct = txt(pc, 394, 54, 100, 20, "0%", C.dim, 16, AR)
    -- 透明滑杆盖在轨道上（真拖动）；两侧 10 段热区做兜底点按
    R.p_slider = theme.slider(pc, 14, 38, 480, 6, 0, function(_, v)
        if R.p_syncing then return end
        v = tonumber(v)
        if not v and R.p_slider then
            pcall(function() v = R.p_slider:get_value() end)
        end
        v = tonumber(v)
        if not v then return end
        local tr = mock.track(P.i)
        P.t = math.floor(tr.d * v / 100)
        M.refresh_time()
    end)
    return pc
end

--------------------------------------------------------------------
-- 控制条：模式 / 上一首 / 播放 / 下一首 / 音量 / 收藏
--------------------------------------------------------------------
local function draw_vol_bar()
    local w = math.floor(82 * S.vol / 100)
    put(R.vol_fill, (w > 2) and { rc(0, 0, w, 4, C.ac, 2) } or {})
    call(R.vol_knob, "set_pos", 422 + w - 5, 5)
end

local function build_ctrl(scr)
    -- html 的 .ctrl 没有卡片底/边框，只有一行 flex
    local ct = theme.box(scr, 416, 204, 508, 80, C.bg)

    local mb = theme.box_b(ct, 14, 6, 46, 46, C.btn, 10, C.line, 1)
    R.mode_ic = theme.icon(mb, 11, 11, 24, 24, airui.SYMBOL_LOOP, C.sub, 22)
    R.mode_lb = txt(ct, 4, 54, 68, 20, mock.MODES[1], C.dim, 16, AC)
    theme.hit(ct, 4, 6, 68, 68, function() M.cycle_mode() end)

    -- 76px 播放键：整颗琥珀实色，内置符号白色
    theme.circle(ct, 216, 2, 76, C.playbg)
    R.play_ic = theme.icon(ct, 239, 30, 30, 20, airui.SYMBOL_PLAY, C.white, 20)
    theme.hit(ct, 216, 2, 76, 76, function() M.toggle_play() end)

    local prv = airui.container({ parent = ct, x = 152, y = 14, w = 52, h = 52,
        color = C.btn, radius = 26, border_color = C.line, border_width = 1 })
    theme.register(prv, function() return C.btn end)
    theme.register(prv, function() return C.line end, nil, true)
    R.prev_ic = theme.icon(prv, 16, 16, 20, 20, airui.SYMBOL_PREV, C.text, 20)
    theme.hit(ct, 152, 14, 52, 52, function() M.step(-1) end)

    local nxt = airui.container({ parent = ct, x = 304, y = 14, w = 52, h = 52,
        color = C.btn, radius = 26, border_color = C.line, border_width = 1 })
    theme.register(nxt, function() return C.btn end)
    theme.register(nxt, function() return C.line end, nil, true)
    R.next_ic = theme.icon(nxt, 16, 16, 20, 20, airui.SYMBOL_NEXT, C.text, 20)
    theme.hit(ct, 304, 14, 52, 52, function() M.step(1) end)

    R.fav_bg = theme.box_b(ct, 466, 18, 38, 38, C.btn, 12, C.line, 1)
    R.fav_sh = theme.shape(R.fav_bg, 10, 10, 18, 18)
    theme.hit(ct, 466, 18, 38, 38, function() M.toggle_fav(P.i) end)

    R.vol_ic = theme.icon(ct, 392, 2, 22, 22, airui.SYMBOL_VOLUME_MID, C.dim, 20)
    theme.box(ct, 422, 8, 82, 4, C.track, 2)
    R.vol_fill = theme.shape(ct, 422, 8, 82, 4)
    R.vol_knob = theme.circle(ct, 422 + math.floor(82 * S.vol / 100) - 5, 5, 10, C.ac)
    R.vol_lb = txt(ct, 374, 58, 130, 20, "VOL 68", C.dim, 16, AR)
    local function on_vol(_, v)
        if R.vol_syncing then return end
        v = tonumber(v)
        if not v and R.vol_slider then
            pcall(function() v = R.vol_slider:get_value() end)
        end
        v = tonumber(v)
        if not v then return end
        v = math.max(0, math.min(100, math.floor(v)))
        if v == S.vol then return end
        S.vol = v
        -- 拖动时只画线条和圆点；音量命令与文字放到 100ms 任务里合并，
        -- 避免每个触摸事件都刷文字/滑块/soft_volume 造成几秒积压。
        R.vol_pending = v
        draw_vol_bar()
    end
    local ok_sl, sl = pcall(airui.slider, {
        parent = ct, x = 410, y = 0, w = 96, h = 28,
        min = 0, max = 100, value = math.floor(S.vol),
        style = { bg_opa = 0, indicator_opa = 0, knob_opa = 0,
            border_width = 0, radius = 14, pad = 0 },
        on_change = on_vol,
    })
    if ok_sl and sl then
        R.vol_slider = sl
    else
        R.vol_slider = theme.slider(ct, 422, 8, 82, 4, S.vol, on_vol)
    end
    R.vol_audio = S.vol
    return ct
end

--------------------------------------------------------------------
-- 播放队列（5 行，从当前曲目起循环取；行内可点、可收藏）
--------------------------------------------------------------------
local function build_queue(scr)
    local qc = theme.box_b(scr, 416, 295, 508, 245, C.card, 12, C.line, 1)
    txt(qc, 14, 8, 300, 20, "播放队列 / QUEUE", C.dim, 16, AL)
    R.q_count = txt(qc, 314, 8, 180, 20, "08 TRACKS", C.dim, 16, AR)

    R.q_rows = {}
    for k = 1, 5 do
        local y = 35 + (k - 1) * 36
        local bg = airui.container({ parent = qc, x = 8, y = y, w = 492, h = 36,
            color = C.card2, radius = 6 })
        pcall(bg.set_color, bg, C.card2, 0)
        local row = { bg = bg }
        row.no = txt(bg, 8, 0, 26, 36, "", C.dim, 16, AR)
        row.eq = theme.shape(bg, 40, 11, 16, 14)
        row.nm = txt(bg, 62, 0, 224, 36, "", C.text, 18, AL)
        row.ar = txt(bg, 292, 0, 136, 36, "", C.dim, 16, AL)
        row.du = txt(bg, 424, 0, 62, 36, "", C.dim, 16, AL)
        theme.hit(bg, 0, 0, 492, 36, function() M.goto_track(row.idx) end)
        R.q_rows[k] = row
    end
    return qc
end

--------------------------------------------------------------------
-- 曲库屏（scr_lib）：标题 / 工具条 / 曲目表 / 分页 / 新增面板
--------------------------------------------------------------------
-- 表格列（相对卡片左边缘）：# / 播放态 / 曲名 / 艺术家 / 专辑 / 格式 / 时长 / 收藏
local COLS = {
    { x = 10,  w = 34,  align = AR },
    { x = 54,  w = 14 },
    { x = 78,  w = 245 },
    { x = 333, w = 189 },
    { x = 532, w = 152 },
    { x = 694, w = 80 },
    { x = 784, w = 56 },
}
local HEAD = { "#", "", "曲名", "艺术家", "专辑", "格式", "时长" }

local function table_rows(card, n, on_row, on_star)
    local rows = {}
    for k = 1, n do
        local y = 42 + (k - 1) * 40
        local bg = airui.container({ parent = card, x = 4, y = y, w = 892, h = 40,
            color = C.card, radius = 6 })
        pcall(bg.set_color, bg, C.card, 0)
        local row = { bg = bg }
        row.c = {}
        for i = 1, #COLS do
            row.c[i] = txt(bg, COLS[i].x - 4, 0, COLS[i].w, 40, "",
                (i == 1) and C.dim or C.sub, (i == 3) and 18 or 16, COLS[i].align)
        end
        row.eq = theme.shape(bg, 50, 13, 16, 14)
        row.st = theme.shape(bg, 850, 10, 18, 18)
        theme.hit(bg, 0, 0, 840, 40, function() if row.idx then on_row(row.idx) end end)
        theme.hit(bg, 840, 0, 52, 40, function() if row.idx then on_star(row.idx) end end)
        rows[k] = row
    end
    return rows
end

local function build_lib(root)
    local scr = theme.box(root, NAV_W, TOP_H, W - NAV_W, H - TOP_H - MINI_H, C.bg)
    R.scr_lib = scr
    build_grid(scr, NAV_W, TOP_H, W - NAV_W, H - TOP_H - MINI_H)

    txt(scr, PX, PY, 300, 26, "曲库 / LIBRARY", C.text, 20, AL)
    R.lib_sub = txt(scr, PX, PY + 28, 560, 20, "", C.dim, 16, AL)
    R.lib_add = theme.pill(scr, 760, PY, 164, 40, "+ 自定义曲目", 16,
        function() M.toggle_add() end, false)

    -- 工具条
    local bar = theme.box(scr, PX, 76, 900, 40, C.bg)
    R.lib_bar = bar
    theme.box_b(bar, 0, 0, 360, 40, C.panel2, 10, C.line, 1)
    R.lib_search_ic = theme.shape(bar, 12, 11, 18, 18)
    put(R.lib_search_ic, theme.IC.search(18, 18, C.dim))
    R.lib_q = txt(bar, 40, 0, 280, 40, "搜索曲名 / 艺术家 / 专辑", C.dim, 16, AL)
    theme.hit(bar, 0, 0, 320, 40, function() M.open_search_input() end)
    theme.hit(bar, 324, 0, 36, 40, function() M.clear_query() end)
    R.lib_clear = txt(bar, 324, 0, 36, 40, "×", C.dim, 18, AC)

    R.lib_fmt = theme.segs(bar, 372, 0, 200, 40, mock.FMTS, P.fmt_i, function(i)
        P.fmt_i = i
        S.fmt = mock.FMT_KEYS[i]
        R.lib_fmt.set(i)
        M.refresh_lib()
    end)
    R.sort_btn = airui.container({ parent = bar, x = 584, y = 0, w = 140, h = 40,
        color = C.btn, radius = 8, border_color = C.line2, border_width = 1 })
    theme.register(R.sort_btn, function() return C.btn end)
    theme.register(R.sort_btn, function() return C.line2 end, nil, true)
    R.lib_sort_lb = txt(R.sort_btn, 10, 0, 104, 40, mock.SORTS[P.sort_i], C.dim, 16, AL)
    R.sort_arrow = theme.shape(R.sort_btn, 116, 16, 12, 10)
    put(R.sort_arrow, { ln(1, 2, 6, 7, C.dim, 2), ln(11, 2, 6, 7, C.dim, 2) })
    theme.hit(bar, 584, 0, 140, 40, function() M.toggle_sort_menu() end)

    theme.pill(bar, 736, 0, 164, 40, "重新扫描", 16,
        function() M.rescan() end, false)

    return scr
end

local function build_lib_table(scr)
    local card = theme.box(scr, PX, 128, 900, 292, C.card, 12)
    R.lib_card = card

    local hr = card
    for i = 1, #COLS do
        txt(hr, COLS[i].x - 4, 4, COLS[i].w, 34, HEAD[i], C.dim, 16, COLS[i].align)
    end
    txt(hr, 850, 4, 50, 34, "收藏", C.dim, 16, AL)

    R.lib_rows = table_rows(card, 6,
        function(i) M.goto_track(i) end,
        function(i) M.toggle_fav(i) end)

    -- 空态（无 SD / 无匹配）
    local empty = theme.box(scr, PX, 128, 900, 292, C.card, 12)
    R.lib_empty = empty
    R.lib_empty_t = txt(empty, 0, 110, 900, 26, "未找到曲目", C.sub, 18, AC)
    R.lib_empty_s = txt(empty, 0, 144, 900, 22,
        "请检查 Micro-SD 或调整筛选条件", C.dim, 16, AC)
    set_hidden(empty, true)

    -- 分页（箭头用图元画，避开字库缺 ‹ › 字形）
    R.lib_pager = theme.box(scr, 600, 430, 300, 32, C.bg)
    R.lib_page = txt(R.lib_pager, 0, 0, 200, 32, "", C.dim, 16, AR)
    R.pager_sh = {}
    local function pager_arrow(x, left)
        local b = airui.container({ parent = R.lib_pager, x = x, y = 0, w = 40, h = 32,
            color = C.btn, radius = 7, border_color = C.line2, border_width = 1 })
        theme.register(b, function() return C.btn end)
        theme.register(b, function() return C.line2 end, nil, true)
        local sh = theme.shape(b, 14, 10, 12, 12)
        if left then
            put(sh, { ln(9, 1, 3, 6, C.dim, 2), ln(3, 6, 9, 11, C.dim, 2) })
        else
            put(sh, { ln(3, 1, 9, 6, C.dim, 2), ln(9, 6, 3, 11, C.dim, 2) })
        end
        R.pager_sh[#R.pager_sh + 1] = sh
        return b
    end
    pager_arrow(206, true)
    theme.hit(R.lib_pager, 206, 0, 40, 32, function() M.lib_turn(-1) end)
    pager_arrow(250, false)
    theme.hit(R.lib_pager, 250, 0, 40, 32, function() M.lib_turn(1) end)

    -- 排序下拉框（对应 html 的 select，展开后浮在表格上方）
    -- 不加滚动条/选中条，选项之间留足行距
    R.sort_menu = airui.container({ parent = scr, x = PX + 584, y = 120, w = 140, h = 184,
        color = C.card, radius = 8, border_width = 0 })
    theme.register(R.sort_menu, function() return C.card end)
    R.sort_items = {}
    for i = 1, #mock.SORTS do
        local iy = (i - 1) * 46
        local bg = airui.container({ parent = R.sort_menu, x = 0, y = iy, w = 140, h = 46,
            color = C.card })
        local lb = txt(bg, 10, 0, 120, 46, mock.SORTS[i], C.sub, 16, AL)
        theme.hit(R.sort_menu, 0, iy, 140, 46, function() M.set_sort(i) end)
        R.sort_items[i] = { bg = bg, lb = lb }
    end
    set_hidden(R.sort_menu, true)

    -- 新增曲目面板（文案与 html 的 addpanel 一致；真机无软键盘，字段为演示值）
    local pa = theme.box_b(scr, PX, 76, 900, 128, C.panel, 12, C.acline, 1)
    R.add_panel = pa
    set_hidden(pa, true)
    txt(pa, 14, 6, 400, 20, "添加曲目到本机曲库", C.dim, 16, AL)
    txt(pa, 414, 6, 472, 20, "会话内生效，固化请改 T 数组", C.dim, 16, AR)
    local flds = { { 14, 150, "曲名" }, { 172, 130, "艺术家" }, { 310, 74, "240" } }
    for i = 1, #flds do
        local f = flds[i]
        theme.box_b(pa, f[1], 32, f[2], 40, C.bg2, 7, C.line2, 1)
        txt(pa, f[1] + 8, 32, f[2] - 16, 40, f[3], C.dim, 16, AL)
    end
    local bx = {
        { 392, 110, "选择封面图" }, { 510, 100, "选择音频" },
        { 618, 120, "添加并播放" }, { 746, 76, "取消" },
    }
    local function addpill(b, pri, fn)
        theme.pill(pa, b[1], 32, b[2], 40, b[3], 16, fn, pri)
    end
    addpill(bx[1], true, function() M.toast("演示模式：封面用内置几何图") end)
    addpill(bx[2], true, function() M.toast("演示模式：音频用本地 WAV / 合成兜底") end)
    addpill(bx[3], true, function() M.add_track() end)
    addpill(bx[4], false, function() M.cancel_add() end)
    R.add_hint = txt(pa, 14, 80, 872, 34,
        "未选择图片用内置几何封面；未选择音频用本地 WAV / 合成兜底", C.dim, 16, AL)
    return card
end

--------------------------------------------------------------------
-- 收藏屏（scr_fav）
--------------------------------------------------------------------
local function build_fav(root)
    local scr = theme.box(root, NAV_W, TOP_H, W - NAV_W, H - TOP_H - MINI_H, C.bg)
    R.scr_fav = scr
    build_grid(scr, NAV_W, TOP_H, W - NAV_W, H - TOP_H - MINI_H)

    txt(scr, PX, PY, 400, 26, "收藏 / FAVORITES", C.text, 20, AL)
    R.fav_sub = txt(scr, PX, PY + 28, 500, 20, "", C.dim, 16, AL)
    theme.pill(scr, 720, PY, 92, 40, "播放全部", 16, function()
        M.play_all_fav()
    end, true)
    R.fav_clear = theme.pill(scr, 820, PY, 104, 40, "清空收藏", 16, function()
        M.clear_fav()
    end, false)

    -- 统计条
    local sb = theme.box(scr, PX, 76, 900, 56, C.bg)
    R.fav_stat = {}
    local labs = { "收藏曲目", "总时长", "占用空间" }
    for i = 1, 3 do
        local x = (i - 1) * 303
        theme.box_b(sb, x, 0, 293, 56, C.card, 10, C.line, 1)
        txt(sb, x + 14, 0, 150, 56, labs[i], C.dim, 16, AL)
        R.fav_stat[i] = txt(sb, x + 150, 0, 129, 56, "0", C.text, 20, AR)
    end

    local card = theme.box(scr, PX, 144, 900, 292, C.card, 12)
    local hr = card
    for i = 1, #COLS do
        txt(hr, COLS[i].x - 4, 4, COLS[i].w, 34, HEAD[i], C.dim, 16, COLS[i].align)
    end
    txt(hr, 850, 4, 50, 34, "移除", C.dim, 16, AL)

    R.fav_rows = table_rows(card, 6,
        function(i) M.goto_track(i) end,
        function(i) M.toggle_fav(i) end)

    local empty = theme.box(scr, PX, 144, 900, 292, C.card, 12)
    R.fav_empty = empty
    local eh = theme.shape(empty, 431, 88, 38, 38)
    put(eh, theme.IC.heart(38, 38, C.dim, false))
    txt(empty, 0, 134, 900, 26, "还没有收藏曲目", C.sub, 18, AC)
    txt(empty, 0, 168, 900, 22, "在曲库点星标，或在播放页点爱心加入收藏", C.dim, 16, AC)
    set_hidden(empty, true)
    return scr
end

--------------------------------------------------------------------
-- 设置屏（scr_set）：左卡 外观+音频 / 右卡 存储+硬件
--------------------------------------------------------------------
local function grp(card, y, text)
    txt(card, 14, y, 300, 22, text, C.ac, 16, AL)
    theme.box(card, 14, y + 22, 415, 1, C.line)
end

local function srow(card, y, text)
    txt(card, 14, y, 170, 36, text, C.sub, 16, AL)
end

local SW_LABEL = {
    sd = "Micro-SD 状态", sound = "演示音源", spectrum = "频谱显示",
    clock24 = "24 小时制", resume = "断点记忆",
}
local function sw_toast(key, on)
    M.toast((SW_LABEL[key] or key) .. "：" .. (on and "开启" or "关闭"))
end

local function build_set_left(scr)
    local card = theme.box(scr, PX, 76, 443, 408, C.card, 12)
    grp(card, 12, "外观 / APPEARANCE")

    srow(card, 48, "主题模式")
    R.set_theme = theme.segs(card, 230, 50, 199, 32,
        { "白天", "夜间", "自动" }, 1, function(i)
            M.set_theme_mode(i)
        end)

    srow(card, 92, "强调色")
    R.set_accent = theme.segs(card, 230, 94, 199, 32,
        { "琥珀", "冷青", "暖铜" }, 1, function(i) M.set_accent(i) end)

    srow(card, 136, "频谱显示")
    R.sw_spec = theme.switch(card, 385, 140, S.spectrum)
    theme.hit(card, 14, 136, 415, 40, function()
        S.spectrum = not S.spectrum
        theme.sw_set(R.sw_spec, S.spectrum)
        M.refresh_spec_state()
        sw_toast("spectrum", S.spectrum)
    end)

    srow(card, 180, "24 小时制")
    R.sw_clock = theme.switch(card, 385, 184, S.clock24)
    theme.hit(card, 14, 180, 415, 40, function()
        S.clock24 = not S.clock24
        theme.sw_set(R.sw_clock, S.clock24)
        M.refresh_clock()
        sw_toast("clock24", S.clock24)
    end)

    grp(card, 224, "音频 / AUDIO")
    srow(card, 252, "音源输出")
    R.set_src = txt(card, 266, 252, 110, 36, mock.SRC_SET, C.dim, 16, AR)
    R.sw_src = theme.switch(card, 385, 256, S.sound)
    theme.hit(card, 14, 252, 415, 40, function()
        S.sound = not S.sound
        theme.sw_set(R.sw_src, S.sound)
        set_text(R.set_src, mock.SRC_SET)
        sw_toast("sound", S.sound)
    end)

    srow(card, 300, "音效预设")
    R.eq_sh = theme.shape(card, 118, 308, 60, 22)
    R.set_eq = theme.segs(card, 188, 302, 225, 32, mock.EQ_NAMES, S.eq + 1,
        function(i) M.set_eq(i) end)

    srow(card, 348, "断点记忆")
    R.sw_resume = theme.switch(card, 385, 352, S.resume)
    theme.hit(card, 14, 348, 415, 40, function()
        S.resume = not S.resume
        theme.sw_set(R.sw_resume, S.resume)
        sw_toast("resume", S.resume)
    end)
    return card
end

local function build_set_right(scr)
    local card = theme.box(scr, 481, 76, 443, 408, C.card, 12)
    grp(card, 12, "存储 / STORAGE")

    srow(card, 38, "Micro-SD 卡")
    R.sw_sd = theme.switch(card, 385, 42, S.sd)
    theme.hit(card, 14, 38, 415, 40, function() M.toggle_sd() end)

    theme.box(card, 14, 82, 415, 8, C.track, 4)
    R.sd_fill = theme.shape(card, 14, 82, 415, 8)
    R.sd_note = txt(card, 14, 94, 300, 18, "已用 18.6 GB / 32 GB", C.dim, 16, AL)
    R.sd_pct = txt(card, 314, 94, 115, 18, "62%", C.dim, 16, AR)

    grp(card, 134, "硬件 / DEVICE")
    local hw = {
        { "主控", "Air1603" },
        { "显示", "1024 × 600 / RGB565" },
        { "输出", "4Ω 3W 扬声器" },
        { "框架", "LuatOS + AirUI (LVGL 9.4)" },
        { "音源路径", "./audio/ · 真机 /sd/MUSIC/" },
    }
    for i = 1, #hw do
        local y = 160 + (i - 1) * 32
        txt(card, 14, y, 100, 26, hw[i][1], C.dim, 16, AL)
        txt(card, 118, y, 311, 26, hw[i][2], C.sub, 16, AR)
        if i < #hw then
            theme.box(card, 14, y + 30, 415, 1, C.line)
        end
    end
    theme.pill(card, 14, 340, 415, 40, "恢复默认设置", 16, function()
        M.reset_settings()
    end, false)
    return card
end

local function build_set(root)
    local scr = theme.box(root, NAV_W, TOP_H, W - NAV_W, H - TOP_H - MINI_H, C.bg)
    R.scr_set = scr
    build_grid(scr, NAV_W, TOP_H, W - NAV_W, H - TOP_H - MINI_H)
    txt(scr, PX, PY, 400, 26, "设置 / SETTINGS", C.text, 20, AL)
    R.set_sub = txt(scr, PX, PY + 28, 500, 20, "", C.dim, 16, AL)
    R.set_now = txt(scr, 524, PY + 28, 400, 20, "", C.dim, 16, AR)

    build_set_left(scr)
    build_set_right(scr)
    return scr
end

--------------------------------------------------------------------
-- 迷你播放条（非播放屏时出现，对应 html 的 .mini）
--------------------------------------------------------------------
local function build_mini(root)
    local bar = theme.box(root, 0, MINI_Y, W, MINI_H, C.panel)
    R.mini = bar
    theme.box(bar, 0, 0, W, 1, C.mini_border)
    theme.box(bar, 0, 1, W, 27, C.card)   -- 近似 html 的 --hd 上下渐变
    build_grid(bar, 0, MINI_Y, W, MINI_H)

    theme.box_b(bar, 14, 9, 38, 38, C.card2, 6, C.mini_border, 1)
    R.mini_cover = theme.shape(bar, 14, 9, 38, 38)
    R.mini_name = txt(bar, 64, 8, 166, 20, "", C.text, 16, AL)
    R.mini_artist = txt(bar, 64, 28, 166, 18, "", C.mini, 16, AL)

    theme.box(bar, 242, 26, 484, 4, C.track2, 2)
    R.mini_fill = theme.shape(bar, 242, 26, 484, 4)
    R.mini_knob = theme.circle(bar, 242, 22, 12, C.ac)
    R.mini_slider = theme.slider(bar, 242, 26, 484, 4, 0, function(_, v)
        if R.p_syncing then return end
        v = tonumber(v)
        if not v and R.mini_slider then
            pcall(function() v = R.mini_slider:get_value() end)
        end
        v = tonumber(v)
        if not v then return end
        local tr = mock.track(P.i)
        P.t = math.floor(tr.d * v / 100)
        M.refresh_time()
    end)
    R.mini_time = txt(bar, 738, 18, 52, 20, "", C.mini, 16, AL)

    local pb1 = airui.container({ parent = bar, x = 802, y = 11, w = 34, h = 34,
        color = C.btn2, radius = 8, border_color = C.mini_border, border_width = 1 })
    theme.register(pb1, function() return C.btn2 end)
    theme.register(pb1, function() return C.mini_border end, nil, true)
    R.mini_prev = theme.icon(pb1, 6, 6, 22, 22, airui.SYMBOL_PREV, C.text, 22)
    theme.circle(bar, 844, 9, 38, C.playbg)
    R.mini_play = theme.icon(bar, 852, 17, 22, 22, airui.SYMBOL_PLAY, C.white, 22)
    local pb2 = airui.container({ parent = bar, x = 890, y = 11, w = 34, h = 34,
        color = C.btn2, radius = 8, border_color = C.mini_border, border_width = 1 })
    theme.register(pb2, function() return C.btn2 end)
    theme.register(pb2, function() return C.mini_border end, nil, true)
    R.mini_next = theme.icon(pb2, 6, 6, 22, 22, airui.SYMBOL_NEXT, C.text, 22)
    theme.hit(bar, 802, 11, 34, 34, function() M.step(-1) end)
    theme.hit(bar, 844, 9, 38, 38, function() M.toggle_play() end)
    theme.hit(bar, 890, 11, 34, 34, function() M.step(1) end)

    R.mini_vol = txt(bar, 936, 18, 68, 20, "VOL 68", C.mini, 16, AR)
    return bar
end

--------------------------------------------------------------------
-- toast（1.9s 自动消失；只改文本 + 显隐，不销毁）
--------------------------------------------------------------------
local function build_toast(root)
    local t = airui.container({ parent = root, x = 382, y = 490, w = 260,
        h = 38, color = C.toast_bg, radius = 8,
        border_color = C.acline, border_width = 1 })
    R.toast = t
    theme.register(t, function() return C.toast_bg end)
    theme.register(t, function() return C.acline end, nil, true)
    R.toast_lb = txt(t, 12, 0, 236, 38, "", C.toast_tx, 16, AC)
    set_hidden(t, true)
    return t
end

--------------------------------------------------------------------
-- 刷新：播放态 / 时间 / 音量 / 频谱 / 时钟
--------------------------------------------------------------------
local function track_has_audio(i)
    local tr = mock.track(i)
    return tr and tr.audio == true
end

local function duration_s()
    local tr = mock.track(P.i)
    if tr and tr.audio and app_audio and app_audio.started() then
        local d = app_audio.duration_ms()
        if d and d > 0 then return d / 1000 end
    end
    return tr and tr.d or 0
end

local function progress_pct()
    local d = duration_s()
    local p = (d > 0) and (P.t / d) or 0
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    return p
end

local function draw_progress()
    local p = progress_pct()
    local pct = math.floor(p * 100 + 0.5)
    local w = math.floor(480 * p)
    put(R.p_fill, (w > 2) and { rc(0, 0, w, 6, C.ac, 3) } or {})
    call(R.p_knob, "set_pos", 14 + w - 6, 35)
    local mw = math.floor(484 * p)
    put(R.mini_fill, (mw > 2) and { rc(0, 0, mw, 4, C.ac, 2) } or {})
    call(R.mini_knob, "set_pos", 242 + mw - 6, 22)
    call(R.p_slider, "set_value", pct, false)
    call(R.mini_slider, "set_value", pct, false)
end

-- 每帧只刷线和圆点，让进度条与真实音频连续对接；文字仍每秒刷一次
function M.refresh_progress()
    if not R or R.p_syncing then return end
    R.p_syncing = true
    pcall(draw_progress)
    R.p_syncing = false
end

function M.refresh_time()
    if not R or R.p_syncing then return end
    R.p_syncing = true
    pcall(function()
        local p = progress_pct()
        set_text(R.p_cur, mock.fmt_t(P.t))
        set_text(R.p_dur, mock.fmt_t(math.floor(duration_s() + 0.5)))
        set_text(R.p_pct, math.floor(p * 100 + 0.5) .. "%")
        set_text(R.mini_time, mock.fmt_t(P.t))
        draw_progress()
    end)
    R.p_syncing = false
end

function M.refresh_vol(sync_slider)
    if not R or R.vol_syncing then return end
    R.vol_syncing = true
    pcall(function()
        draw_vol_bar()
        set_text(R.vol_lb, "VOL " .. S.vol)
        set_text(R.mini_vol, "VOL " .. S.vol)
        -- 拖动过程中不要回写滑块，避免和手指抢值
        if sync_slider ~= false then
            call(R.vol_slider, "set_value", S.vol, false)
        end
    end)
    R.vol_syncing = false
end

function M.refresh_clock()
    local ok, t = pcall(os.date, "*t")
    if not ok or not t then set_text(R.clock, "--:--") return end
    local s
    if S.clock24 then
        s = string.format("%02d:%02d", t.hour, t.min)
    else
        local h = t.hour % 12
        if h == 0 then h = 12 end
        s = string.format("%02d:%02d %s", h, t.min, (t.hour < 12) and "AM" or "PM")
    end
    set_text(R.clock, s)
end

-- 频谱：40 根柱拆成 2 个 shape（单 shape 图元上限 32）
function M.refresh_spec_state()
    R.spec_idle = false
    M.refresh_spec()
end

function M.refresh_spec()
    if not R or not R.spec_a or not R.spec_b then return end
    if P.page ~= "play" then return end
    local on = S.spectrum and P.playing
    if not on and R.spec_idle then
        -- 已经画成静止细线，不必每帧重画（静态也 set_items 会白烧 CPU）
        return
    end
    R.spec_idle = not on
    R.phase = (R.phase or 0) + 0.17
    local h1, h2 = {}, {}
    for i = 1, 40 do
        local target
        if on then
            local a = math.abs(math.sin(i * 0.41 + R.phase))
            local b = math.abs(math.sin(i * 0.17 - R.phase * 0.6))
            target = 0.20 + 0.72 * (a * 0.65 + b * 0.35)
        else
            target = 0.09
        end
        local cur = R.bars[i] or target
        cur = (target > cur) and (cur + (target - cur) * 0.55)
                             or (cur + (target - cur) * 0.22)
        R.bars[i] = cur
        local hh = math.max(2, math.floor(cur * 38))
        local base = (i % 3 == 0) and C.bar2 or C.ac
        local col = on and base or theme.mix(base, C.bg, 0.62)
        local bx = ((i - 1) % 20) * 12
        local it = rc(bx, 38 - hh, 9, hh, col, 0)
        if i <= 20 then h1[#h1 + 1] = it else h2[#h2 + 1] = it end
    end
    R.spec_on = on
    put(R.spec_a, h1)
    put(R.spec_b, h2)
end

function M.begin_cover_fade()
    if not R.cover_fade then return end
    local gen = (R.fade_gen or 0) + 1
    R.fade_gen = gen
    pcall(R.cover_fade.set_color, R.cover_fade, C.bg2, 255)
    local step = 0
    local function tick()
        if M.gen ~= R.gen or R.fade_gen ~= gen then return end
        step = step + 1
        local opa = 255 - math.floor(255 * step / 8)
        if opa <= 0 then
            pcall(R.cover_fade.set_color, R.cover_fade, C.bg2, 0)
            return
        end
        pcall(R.cover_fade.set_color, R.cover_fade, C.bg2, opa)
        sys.timerStart(tick, 30)
    end
    sys.timerStart(tick, 30)
end

-- 播放模式图标：0 列表循环 / 1 单曲循环 / 2 随机
local function mode_items(mode, col)
    local it = {}
    if mode == 2 then
        -- 随机：两条交叉箭头（对应 html 的 m2 路径）
        it[#it + 1] = ln(2, 5, 7, 5, col, 2)
        it[#it + 1] = ln(7, 5, 12, 15, col, 2)
        it[#it + 1] = ln(12, 15, 17, 15, col, 2)
        it[#it + 1] = ln(14, 12, 17, 15, col, 2)
        it[#it + 1] = ln(17, 15, 14, 18, col, 2)
        it[#it + 1] = ln(2, 15, 7, 15, col, 2)
        it[#it + 1] = ln(7, 15, 11, 8, col, 2)
        it[#it + 1] = ln(11, 8, 17, 8, col, 2)
        it[#it + 1] = ln(14, 5, 17, 8, col, 2)
        it[#it + 1] = ln(17, 8, 14, 11, col, 2)
    else
        -- 列表/单曲循环：最简单的矩形闭环 + 两个箭头
        it[#it + 1] = ln(4, 5, 16, 5, col, 2)
        it[#it + 1] = ln(16, 5, 16, 15, col, 2)
        it[#it + 1] = ln(16, 15, 4, 15, col, 2)
        it[#it + 1] = ln(4, 15, 4, 5, col, 2)
        it[#it + 1] = ln(13, 2, 16, 5, col, 2)
        it[#it + 1] = ln(16, 5, 13, 8, col, 2)
        it[#it + 1] = ln(7, 18, 4, 15, col, 2)
        it[#it + 1] = ln(4, 15, 7, 12, col, 2)
        if mode == 1 then
            it[#it + 1] = ln(10, 7, 10, 12, col, 2)
            it[#it + 1] = ln(10, 7, 8, 9, col, 2)
        end
    end
    return it
end

local function refresh_eq(sh, show, col)
    if not show then
        put(sh, {})
        return
    end
    put(sh, { rc(0, 6, 3, 8, col, 1), rc(5, 2, 3, 12, col, 1),
              rc(10, 7, 3, 7, col, 1) })
end

function M.refresh_play()
    local tr = mock.track(P.i)
    if R.cover_idx ~= P.i then
        M.begin_cover_fade()
        put(R.cover, cover_items(tr))
        R.cover_idx = P.i
    end
    set_text(R.cv_album, "JAY CHOU · " .. short_ch(tr.al, 6))
    set_text(R.cv_name, tr.n)
    set_text(R.cv_en, tr.en .. " · " .. tr.yr)
    set_text(R.cv_no, mock.pad2(P.i) .. " / " .. mock.pad2(#mock.TRACKS))

    set_text(R.p_idx, mock.pad2(P.i) .. " / " .. mock.pad2(#mock.TRACKS))
    set_text(R.p_name, tr.n)
    set_text(R.p_artist, tr.a .. " · " .. tr.al)

    set_text(R.p_tag[1], tr.fmt)
    set_text(R.p_tag[2], "ALBUM " .. mock.pad2(P.i))
    set_text(R.p_tag[3], (S.theme == "auto" and "自动 · " or "")
        .. ((theme.mode == "day") and "白天主题" or "夜间主题"))
    set_text(R.p_tag[4], mock.SRC_TAG)
    set_text(R.p_meta, "SD CARD · TRACK " .. mock.pad2(P.i))

    -- 控制键：直接用 AirUI 内置符号
    call(R.play_ic, "set_symbol",
        P.playing and airui.SYMBOL_PAUSE or airui.SYMBOL_PLAY)
    call(R.play_ic, "set_color", C.white)
    call(R.prev_ic, "set_color", C.text)
    call(R.next_ic, "set_color", C.text)
    local has = mock.is_fav(P.i)
    call(R.fav_bg, "set_color", has and C.acw or C.btn, 255)
    call(R.fav_bg, "set_border_color", has and C.acline or C.line)
    put(R.fav_sh, theme.IC.heart(18, 18, has and C.ac or C.sub, has))
    call(R.mode_ic, "set_symbol",
        (S.mode == 2) and airui.SYMBOL_SHUFFLE or airui.SYMBOL_LOOP)
    call(R.mode_ic, "set_color", (S.mode > 0) and C.ac or C.sub)
    set_text(R.mode_lb, mock.MODES[S.mode + 1])
    set_text(R.q_count, mock.pad2(#mock.TRACKS) .. " TRACKS")

    -- 队列（从当前曲目起；只在曲目/播放态变化时重设）
    local qsig = P.i .. "_" .. tostring(P.playing)
    if R.q_sig == qsig then
        M.refresh_time()
        return
    end
    R.q_sig = qsig
    for k = 1, 5 do
        local row = R.q_rows[k]
        local idx = ((P.i - 1 + k - 1) % #mock.TRACKS) + 1
        local t2 = mock.TRACKS[idx]
        row.idx = idx
        set_text(row.no, mock.pad2(idx))
        set_text(row.nm, t2.n)
        set_text(row.ar, t2.a)
        set_text(row.du, mock.fmt_t(t2.d))
        local on = (idx == P.i)
        pcall(row.bg.set_color, row.bg, on and C.acw or C.card2, on and 255 or 0)
        pcall(row.no.set_color, row.no, on and C.ac or C.dim)
        pcall(row.nm.set_color, row.nm, on and C.ac or C.text)
        refresh_eq(row.eq, on and P.playing, t2.c1)
    end
    M.refresh_time()
end

function M.refresh_lib()
    local list = S.sd and mock.filtered() or {}
    local per, total = 6, math.max(1, math.ceil(#list / 6))
    if P.lib_page > total then P.lib_page = total end
    if P.lib_page < 1 then P.lib_page = 1 end

    for k = 1, 6 do
        local row = R.lib_rows[k]
        local idx = list[(P.lib_page - 1) * per + k]
        row.idx = idx
        set_hidden(row.bg, not idx)
        if idx then
            local t2 = mock.TRACKS[idx]
            set_text(row.c[1], mock.pad2((P.lib_page - 1) * per + k))
            set_text(row.c[3], t2.n)
            set_text(row.c[4], t2.a)
            set_text(row.c[5], t2.al)
            set_text(row.c[6], fmt_short(t2.fmt))
            set_text(row.c[7], mock.fmt_t(t2.d))
            pcall(row.bg.set_color, row.bg,
                (idx == P.i) and C.acw or C.card, (idx == P.i) and 255 or 0)
            refresh_eq(row.eq, idx == P.i and P.playing, t2.c1)
            local f = mock.is_fav(idx)
            put(row.st, theme.IC.star(18, 18, f and C.ac or C.line2, f))
        end
    end

    set_text(R.lib_sub, "Micro-SD · /sd/MUSIC · "
        .. mock.pad2(#mock.TRACKS) .. " 首曲目 · 筛选 " .. #list .. " 首")
    set_text(R.lib_page, P.lib_page .. " / " .. total)
    set_text(R.lib_q, "搜索曲名 / 艺术家 / 专辑")
    set_text(R.lib_clear, "×")
    put(R.lib_search_ic, theme.IC.search(18, 18, C.dim))
    put(R.sort_arrow, { ln(1, 2, 6, 7, C.dim, 2), ln(11, 2, 6, 7, C.dim, 2) })
    if R.pager_sh then
        put(R.pager_sh[1], { ln(9, 1, 3, 6, C.dim, 2), ln(3, 6, 9, 11, C.dim, 2) })
        put(R.pager_sh[2], { ln(3, 1, 9, 6, C.dim, 2), ln(9, 6, 3, 11, C.dim, 2) })
    end
    set_text(R.lib_sort_lb, mock.SORTS[P.sort_i])
    if P.add_open then R.sort_open = false end
    set_hidden(R.sort_menu, not R.sort_open)

    local empty = (#list == 0)
    set_hidden(R.lib_card, empty or P.add_open)
    set_hidden(R.lib_empty, (not empty) or P.add_open)
    set_text(R.lib_empty_t, S.sd and "没有匹配的曲目" or "未检测到 Micro-SD 卡")
    set_text(R.lib_empty_s, S.sd and "换个关键词，或把格式筛选切回「全部」"
        or "请插入存储卡后点「重新扫描」，或在设置中恢复介质状态")
    set_hidden(R.add_panel, not P.add_open)
    set_hidden(R.lib_bar, P.add_open)
    set_hidden(R.lib_pager, P.add_open)
end

function M.refresh_fav()
    local fav = S.fav
    for k = 1, 6 do
        local row = R.fav_rows[k]
        local idx = fav[k]
        row.idx = idx
        set_hidden(row.bg, not idx)
        if idx then
            local t2 = mock.TRACKS[idx]
            set_text(row.c[1], mock.pad2(k))
            set_text(row.c[3], t2.n)
            set_text(row.c[4], t2.a)
            set_text(row.c[5], t2.al)
            set_text(row.c[6], fmt_short(t2.fmt))
            set_text(row.c[7], mock.fmt_t(t2.d))
            refresh_eq(row.eq, idx == P.i and P.playing, t2.c1)
            put(row.st, theme.IC.star(18, 18, C.ac, true))
        end
    end

    local sec = 0
    for k = 1, #fav do
        local t2 = mock.TRACKS[fav[k]]
        sec = sec + t2.d
    end
    set_text(R.fav_stat[1], tostring(#fav) .. " 首")
    set_text(R.fav_stat[2], mock.fmt_t(sec))
    set_text(R.fav_stat[3], string.format("%.0f MB", sec * 0.16))
    set_text(R.fav_sub, "本机收藏列表 · 刷新后保留")
    set_text(R.fav_clear.lb, P.confirm_clear and "确认清空？" or "清空收藏")
    local empty = (#fav == 0)
    set_hidden(R.fav_empty, not empty)
    for k = 1, 6 do set_hidden(R.fav_rows[k].bg, true) end
    if not empty then
        for k = 1, math.min(6, #fav) do set_hidden(R.fav_rows[k].bg, false) end
    end
end

function M.refresh_set()
    local day = (theme.mode == "day")
    set_text(R.set_sub, "本机配置写入 localStorage · 真机映射 Lua 配置表")
    set_text(R.set_now, "当前：" .. (day and "白天" or "夜间") .. "主题"
        .. (S.theme == "auto" and "（自动按时间）" or ""))
    set_text(R.set_src, mock.SRC_SET)

    local ti = (S.theme == "night") and 2 or (S.theme == "auto" and 3 or 1)
    if R.set_theme then R.set_theme.set(ti) end
    local ai = 1
    for i = 1, #mock.ACCENTS do
        if mock.ACCENTS[i].key == S.accent then ai = i end
    end
    if R.set_accent then R.set_accent.set(ai) end
    if R.set_eq then R.set_eq.set(S.eq + 1) end

    local vals = mock.EQ_VALS[S.eq + 1]
    local it = {}
    for i = 1, 5 do
        local hh = math.max(4, math.floor(vals[i] * 0.20))
        it[#it + 1] = rc((i - 1) * 12, 22 - hh, 8, hh, C.ac, 2)
    end
    put(R.eq_sh, it)

    local used, cap = 18.6, 32
    local pct = 62
    local w = math.floor(415 * 0.62)
    put(R.sd_fill, { rc(0, 0, w, 8, C.ac, 4) })
    set_text(R.sd_pct, pct .. "%")
    set_text(R.sd_note, string.format("已用 %.1f GB / %d GB", used, cap))
    theme.sw_set(R.sw_sd, S.sd)
    theme.sw_set(R.sw_spec, S.spectrum)
    theme.sw_set(R.sw_clock, S.clock24)
    theme.sw_set(R.sw_src, S.sound)
    theme.sw_set(R.sw_resume, S.resume)
end

function M.refresh_mini()
    local tr = mock.track(P.i)
    put(R.mini_cover, {
        rc(0, 0, 38, 38, tr.g1, 8), rc(0, 19, 38, 19, tr.g2, 8),
        cl(27, 12, 8, tr.c1, 220), rc(0, 0, 3, 38, tr.c1, 1),
    })
    set_text(R.mini_name, tr.n)
    set_text(R.mini_artist, tr.a)
    set_text(R.mini_vol, "VOL " .. S.vol)
    call(R.mini_play, "set_symbol",
        P.playing and airui.SYMBOL_PAUSE or airui.SYMBOL_PLAY)
    call(R.mini_play, "set_color", C.white)
    call(R.mini_prev, "set_color", C.text)
    call(R.mini_next, "set_color", C.text)
    M.refresh_time()
end

--------------------------------------------------------------------
-- toast
--------------------------------------------------------------------
function M.toast(msg)
    if not R.toast then return end
    set_text(R.toast_lb, msg)
    set_hidden(R.toast, false)
    R.toast_seq = (R.toast_seq or 0) + 1
    local seq = R.toast_seq
    sys.timerStart(function()
        if R.toast and R.toast_seq == seq then set_hidden(R.toast, true) end
    end, 1900)
end

--------------------------------------------------------------------
-- 切屏（预建容器 + set_hidden，不重建任何控件）
--------------------------------------------------------------------
function M.goto_page(id)
    local map = { play = R.scr_play, library = R.scr_lib,
                  favorites = R.scr_fav, settings = R.scr_set }
    if not map[id] then return end
    P.page = id
    for k, v in pairs(map) do set_hidden(v, k ~= id) end
    set_hidden(R.mini, id == "play")

    local ni = 1
    for i = 1, #mock.PAGES do
        if mock.PAGES[i].id == id then ni = i end
    end
    for i = 1, 4 do
        local on = (i == ni)
        pcall(R.nav_btn[i].set_color, R.nav_btn[i], on and C.acw or C.nav, 255)
        pcall(R.nav_btn[i].set_border_color, R.nav_btn[i], on and C.acline or C.line)
        if i == 3 then
            put(R.nav_ic[i], theme.IC.heart(21, 21, on and C.ac or C.sub, false))
        else
            pcall(R.nav_ic[i].set_symbol, R.nav_ic[i], nav_symbol(i))
            pcall(R.nav_ic[i].set_color, R.nav_ic[i], on and C.ac or C.sub)
        end
    end
    set_text(R.nav_idx, mock.pad2(ni) .. " / 04")
    local ny = (id == "play") and (H - TOP_H - 38) or (H - TOP_H - MINI_H - 38)
    pcall(R.nav_idx.set_pos, R.nav_idx, 0, ny)
    if R.hd_sub then set_text(R.hd_sub, mock.PAGES[ni].name) end

    if id == "play" then
        R.spec_idle = false
        M.refresh_play()
    elseif id == "library" then M.refresh_lib()
    elseif id == "favorites" then M.refresh_fav()
    elseif id == "settings" then M.refresh_set() end
    if id ~= "play" then M.refresh_mini() end
end

--------------------------------------------------------------------
-- 播放控制
--------------------------------------------------------------------
function M.toggle_play()
    P.playing = not P.playing
    if P.playing then
        -- 无真实音频的曲目也进入播放态，由 100ms 任务走演示进度，只是不出声
        if track_has_audio(P.i) then
            if app_audio then pcall(app_audio.resume_or_play) end
        elseif app_audio then
            pcall(app_audio.stop)
        end
    elseif app_audio then
        pcall(app_audio.stop)
    end
    refresh_all()
end

function M.step(dir)
    if dir < 0 and P.t > 4 then
        P.t = 0
        if app_audio then
            if P.playing and track_has_audio(P.i) then
                pcall(app_audio.play)
            else
                pcall(app_audio.stop)
            end
        end
        M.refresh_time()
        return
    end
    local n = #mock.TRACKS
    if S.mode == 2 and dir > 0 then
        if n > 1 then
            P.i = ((P.i - 1 + math.random(n - 1)) % n) + 1
        else
            P.i = 1
        end
    else
        P.i = ((P.i - 1 + dir) % n) + 1
    end
    P.t = 0
    if app_audio then
        if P.playing and track_has_audio(P.i) then
            pcall(app_audio.play)
        else
            pcall(app_audio.stop)
        end
    end
    refresh_all()
end

function M.goto_track(i)
    if not i then return end
    P.i = i
    P.t = 0
    -- 点任意曲目都进入播放态；只有真实曲目才起播，其余静音走演示进度
    P.playing = true
    if app_audio then
        if track_has_audio(i) then pcall(app_audio.play) else pcall(app_audio.stop) end
    end
    refresh_all()
end

function M.cycle_mode()
    S.mode = (S.mode + 1) % 3
    M.refresh_play()
    M.toast(mock.MODES[S.mode + 1])
end

function M.toggle_fav(i)
    local has = mock.is_fav(i)
    mock.set_fav(i, not has)
    refresh_all()
    M.toast(has and "已取消收藏" or ("已收藏：" .. mock.TRACKS[i].n))
end

--------------------------------------------------------------------
-- 曲库操作
--------------------------------------------------------------------
local QUERIES = { "", "晴天", "周杰伦", "FLAC", "夜曲", "稻香" }

local function destroy_search_obj(o)
    if o then pcall(function() o:destroy() end) end
end

function M.close_search_input()
    if not R.search_open then return end
    if R.search_kb then pcall(R.search_kb.hide, R.search_kb) end
    theme.defer(function()
        destroy_search_obj(R.search_panel)
        destroy_search_obj(R.search_ta)
        destroy_search_obj(R.search_input_bg)
        destroy_search_obj(R.search_kb)
        R.search_panel, R.search_ta, R.search_input_bg, R.search_kb = nil, nil, nil, nil
        R.search_kb_btn, R.search_kb_collapsed = nil, false
        R.search_open = false
    end)
end

function M.submit_search_input()
    local s = ""
    if R.search_ta then
        local ok, text = pcall(function() return R.search_ta:get_text() end)
        if ok and text then s = text end
    end
    P.q, R.qi, P.lib_page = s, 1, 1
    M.close_search_input()
    M.refresh_lib()
end

function M.toggle_search_keyboard()
    if not R.search_open or not R.search_kb then return end
    if not R.search_kb_collapsed then
        pcall(R.search_kb.hide, R.search_kb)
        R.search_kb_collapsed = true
        if R.search_kb_btn then
            pcall(R.search_kb_btn.lb.set_text, R.search_kb_btn.lb, "展开键盘")
        end
        return
    end
    local shown = false
    if R.search_kb.show then
        shown = pcall(R.search_kb.show, R.search_kb)
    end
    if not shown and R.search_kb.set_hidden then
        shown = pcall(R.search_kb.set_hidden, R.search_kb, false)
    end
    if not shown then
        local ok, kb2 = pcall(airui.keyboard, {
            x = 0, y = -(R.search_kb_gap or 20), w = W,
            h = R.search_kb_h or 250, mode = "text", auto_hide = false })
        if ok and kb2 then
            if R.search_ta and R.search_ta.attach_keyboard then
                pcall(R.search_ta.attach_keyboard, R.search_ta, kb2)
            end
            destroy_search_obj(R.search_kb)
            R.search_kb = kb2
            shown = true
        end
    end
    R.search_kb_collapsed = not shown
    if R.search_kb_btn then
        pcall(R.search_kb_btn.lb.set_text, R.search_kb_btn.lb,
            shown and "收起键盘" or "展开键盘")
    end
    if not shown then M.toast("点击输入框可重新弹出键盘") end
end

function M.open_search_input()
    if R.search_open then return end
    -- y=-20 表示键盘底部距屏幕 20px；键盘顶边 = H - 20 - 250 = 330
    local KB_H, KB_GAP = 250, 20
    local kb_top = H - KB_GAP - KB_H
    local ok, kb = pcall(airui.keyboard, {
        x = 0, y = -KB_GAP, w = W, h = KB_H, mode = "text", auto_hide = false })
    if not ok or not kb then
        M.toast("当前固件不支持输入键盘")
        return
    end
    local bar_y = kb_top - 112         -- 整体上移约一行键盘高度，露出更多曲目行
    local input_y = bar_y - 64         -- 输入框回到原搜索工具条附近
    local input_bg = theme.box_a(airui.screen, 76, input_y, 872, 56, C.card, 8, 255)
    local ok2, ta = pcall(airui.textarea, {
        x = 76, y = input_y, w = 872, h = 56, max_len = 64,
        text = P.q or "", placeholder = "搜索曲名 / 艺术家 / 专辑", keyboard = kb })
    if not ok2 or not ta then
        destroy_search_obj(input_bg)
        destroy_search_obj(kb)
        M.toast("当前固件不支持输入框")
        return
    end
    local panel = theme.box_a(airui.screen, 76, bar_y, 872, 52, C.panel, 8, 255)
    R.search_kb, R.search_ta, R.search_panel = kb, ta, panel
    R.search_input_bg = input_bg
    R.search_kb_h, R.search_kb_gap = KB_H, KB_GAP
    R.search_kb_collapsed = false
    R.search_open = true
    R.search_kb_btn = theme.pill(panel, 8, 6, 110, 40, "收起键盘", 16,
        function() M.toggle_search_keyboard() end, false)
    theme.pill(panel, 620, 6, 110, 40, "搜索", 16,
        function() M.submit_search_input() end, true)
    theme.pill(panel, 742, 6, 110, 40, "取消", 16,
        function() M.close_search_input() end, false)
end

function M.cycle_query()
    R.qi = ((R.qi or 1) % #QUERIES) + 1
    P.q = QUERIES[R.qi]
    P.lib_page = 1
    M.refresh_lib()
end

function M.clear_query()
    if P.q == "" then return end
    P.q = ""
    R.qi = 1
    P.lib_page = 1
    M.refresh_lib()
end

function M.toggle_sort_menu()
    if not R.sort_menu then return end
    R.sort_open = not R.sort_open
    set_hidden(R.sort_menu, not R.sort_open)
    if R.sort_btn then
        pcall(R.sort_btn.set_color, R.sort_btn, R.sort_open and C.ac or C.btn, 255)
    end
    pcall(R.lib_sort_lb.set_color, R.lib_sort_lb, R.sort_open and C.white or C.dim)
    if R.sort_open and R.sort_items then
        for i = 1, #R.sort_items do
            pcall(R.sort_items[i].bg.set_color, R.sort_items[i].bg, C.card, 255)
            pcall(R.sort_items[i].lb.set_color, R.sort_items[i].lb, C.sub)
        end
    end
end

function M.set_sort(i)
    P.sort_i = i
    S.sort = mock.SORT_KEYS[i]
    P.lib_page = 1
    R.sort_open = false
    set_hidden(R.sort_menu, true)
    if R.sort_btn then pcall(R.sort_btn.set_color, R.sort_btn, C.btn, 255) end
    pcall(R.lib_sort_lb.set_color, R.lib_sort_lb, C.dim)
    set_text(R.lib_sort_lb, mock.SORTS[i])
    M.refresh_lib()
end

function M.lib_turn(d)
    local list = S.sd and mock.filtered() or {}
    local total = math.max(1, math.ceil(#list / 6))
    P.lib_page = P.lib_page + d
    if P.lib_page < 1 then P.lib_page = 1 end
    if P.lib_page > total then P.lib_page = total end
    M.refresh_lib()
end

function M.rescan()
    if not S.sd then
        S.sd = true
        M.refresh_set()
        M.refresh_lib()
        M.refresh_source()
        M.toast("已检测到 Micro-SD 卡")
        return
    end
    M.refresh_lib()
    M.toast("扫描完成 · " .. #mock.TRACKS .. " 首曲目")
end

function M.toggle_add()
    P.add_open = not P.add_open
    M.refresh_lib()
end

function M.cancel_add()
    P.add_open = false
    set_text(R.add_hint, "未选择图片时使用内置几何封面")
    M.refresh_lib()
end

function M.add_track()
    local n = 1
    for i = 1, #mock.TRACKS do
        if string.find(mock.TRACKS[i].n, "自定义", 1, true) then n = n + 1 end
    end
    local idx = #mock.TRACKS + 1
    mock.TRACKS[idx] = {
        n = "自定义曲目 " .. mock.pad2(n), en = "CUSTOM TRACK",
        a = "未知艺术家", al = "自定义", yr = 2026, d = 240,
        fmt = "MP3 · 320kbps", art = "simple",
        g1 = 0x8FB8CE, g2 = 0xE3D2AE, c1 = 0xE2B96B, c2 = 0x7FA6BE,
    }
    P.add_open = false
    P.lib_page = math.max(1, math.ceil(#mock.TRACKS / 6))
    M.goto_track(idx)
    M.refresh_lib()
    M.toast("已添加并播放《" .. mock.TRACKS[idx].n .. "》")
end

--------------------------------------------------------------------
-- 收藏操作
--------------------------------------------------------------------
function M.play_all_fav()
    if #S.fav == 0 then
        M.toast("收藏为空")
        return
    end
    M.goto_track(S.fav[1])
    M.goto_page("play")
    M.toast("已开始播放收藏")
end

function M.clear_fav()
    if #S.fav == 0 then
        M.toast("收藏为空")
        return
    end
    if not P.confirm_clear then
        P.confirm_clear = true
        M.refresh_fav()
        sys.timerStart(function()
            if P.confirm_clear then
                P.confirm_clear = false
                if R.fav_clear then M.refresh_fav() end
            end
        end, 3000)
        return
    end
    P.confirm_clear = false
    S.fav = {}
    M.refresh_fav(); M.refresh_play(); M.refresh_lib()
    M.toast("已清空收藏")
end

--------------------------------------------------------------------
-- 设置操作（改配色 → 必须整页重建：已建控件的颜色不会自己变）
--------------------------------------------------------------------
local function rebuild(msg)
    theme.defer(function()
        theme.recolor()
        if R.theme_lb then
            set_text(R.theme_lb, (theme.mode == "day") and "白天" or "夜间")
        end
        if R.theme_mark then
            pcall(R.theme_mark.set_pos, R.theme_mark,
                (theme.mode == "day") and 13 or 25, 10)
            put(R.theme_mark, { rc(0, 0, 2, 14, C.dim, 1) })
        end
        R.q_sig = nil
        M.goto_page(P.page)
        M.refresh_source()
        M.refresh_spec_state()
        M.refresh_vol()
        if msg then M.toast(msg) end
    end)
end

function M.set_theme_mode(i)
    S.theme = ({ "day", "night", "auto" })[i] or "day"
    local mode = S.theme
    if mode == "auto" then
        local h = os.date("*t").hour
        mode = (h >= 7 and h < 18) and "day" or "night"
    end
    theme.apply(mode, S.accent)
    rebuild()
end

function M.toggle_theme()
    local mode = (theme.mode == "day") and "night" or "day"
    S.theme = mode
    theme.apply(mode, S.accent)
    rebuild("已切换到" .. (mode == "day" and "白天" or "夜间") .. "主题")
end

function M.set_accent(i)
    local a = mock.ACCENTS[i]
    if not a then return end
    S.accent = a.key
    theme.apply(theme.mode, S.accent)
    rebuild()
end

function M.set_eq(i)
    S.eq = i - 1
    M.refresh_set()
    M.refresh_play()
end

function M.toggle_sd()
    S.sd = not S.sd
    if not S.sd then
        P.playing = false
        if app_audio then pcall(app_audio.stop) end
    end
    M.refresh_set(); M.refresh_lib(); M.refresh_play(); M.refresh_mini()
    M.refresh_source()
    sw_toast("sd", S.sd)
end

function M.reset_settings()
    for k, v in pairs(mock.DEF) do
        if type(v) == "table" then
            local t = {}
            for i = 1, #v do t[i] = v[i] end
            S[k] = t
        else
            S[k] = v
        end
    end
    theme.apply(S.theme, S.accent)
    rebuild("已恢复默认设置")
end

function M.refresh_source()
    if not R or not R.source or not R.source_dot then return end
    local col = S.sd and C.sub or C.warn
    pcall(R.source.set_color, R.source, col)
    pcall(R.source_dot.set_color, R.source_dot, S.sd and C.ac or C.warn, 255)
end

--------------------------------------------------------------------
-- 构建
--------------------------------------------------------------------
M.gen = 0

function M.build(root)
    C = theme.C
    R = { bars = {}, spec_idle = false }
    drawn, tstr = {}, {}
    M.gen = M.gen + 1
    local gen = M.gen
    R.gen = gen

    build_play(root)
    build_prog(R.scr_play)
    build_ctrl(R.scr_play)
    build_queue(R.scr_play)

    build_lib(root)
    build_lib_table(R.scr_lib)
    build_fav(root)
    build_set(root)

    build_nav(root)
    build_top(root)
    build_mini(root)
    build_toast(root)

    M.goto_page(P.page)
    M.refresh_clock()
    M.refresh_source()
    M.refresh_vol()

    sys.taskInit(function()
        local tick = 0
        while M.gen == gen do
            sys.wait(100)
            if M.gen ~= gen then break end
            local ok, err = pcall(function()
                tick = tick + 1
                -- 音量拖动合并到 100ms 一次，避免 soft_volume 和文字刷新排队
                if R.vol_pending then
                    local v = R.vol_pending
                    R.vol_pending = nil
                    if v ~= R.vol_audio then
                        if app_audio then pcall(app_audio.set_volume, v) end
                        R.vol_audio = v
                    end
                    M.refresh_vol(false)
                end
                if app_audio then app_audio.update() end
                M.refresh_spec()
                -- 进度只由 UI 自己的 10 拍=1 秒推进，不再读 app_audio.position_ms()
                -- （当初能完整播放的版本就是这么走的，避免依赖音频时基）
                if P.playing and S.sd then M.refresh_progress() end
                if tick % 10 == 0 then
                    if P.playing and S.sd then
                        P.t = P.t + 1
                        local d = duration_s()
                        if d > 0 and P.t >= d then
                            if S.mode == 1 then
                                P.t = 0
                                if app_audio then
                                    if track_has_audio(P.i) then
                                        pcall(app_audio.play)
                                    else
                                        pcall(app_audio.stop)
                                    end
                                end
                                M.refresh_time()
                            else
                                M.step(1)
                            end
                        else
                            M.refresh_time()
                        end
                    end
                    M.refresh_clock()
                end
            end)
            if not ok then
                pcall(log.error, "music", "tick error: " .. tostring(err))
            end
        end
    end)
end

function M.open()
    theme.open(M.build)
end

function M.close()
    theme.close()
end

return M
