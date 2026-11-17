--[[
@module page_spectrum
@summary 音频频谱 · 音乐律动（AirUI 复刻 audio_spectrum_ui/preview.html）
         实机 1024×600 重排，设计稿 1024×800 等比压缩

         三种可视化模式（环形 / 柱状 / 波形）全部真实动起来，且每一块都能点：
           · 中心唱片      点 → 播放 / 暂停
           · 环形柱        16 个扇形热区，点 → 选中该段谱线（变白加粗 + 顶部读数）
           · 柱状柱        12 个竖向热区，点 → 同上
           · 波形          点 → 保持定格 / 实时刷新
           · 左右侧柱      点 → 按位置锁定 低频 / 中频 / 高频
           · 右侧频段行    点 → 锁定 / 取消该频段（其余谱线变暗）
           · 实时 chip     开 = 实时刷新；关 = 整块频谱冻结 + 中央"已冻结"卡片
           · 采样率 chip   48→44.1→96 kHz，谱线数 48→36→72 根（肉眼可见）
           · 声道 chip     立体声→单声道，频谱左右完全对称
           · 深浅 chip     深色 / 浅色主题切换（切完重建整页）
           · 底栏          封面/播放/上一首/下一首/进度条拖动/三个模式按钮

         踩坑要点见 theme.lua 头部；本页额外注意：
           1. 每帧重建 items 表后统一走 put()，空图元/状态没变时不再 set_items
              （set_items 内部无条件 invalidate，空 shape 也全刷会把 LVGL 堆打爆 →
               HardFault 死机，见下方 put() 注释）。
           2. 点击回调里只改状态 + set_color/set_text/set_hidden，绝不重建子树。
           3. 动态 shape 的容器范围盖住整块图形（超出会被裁剪）。
           4. 图元坐标一律取整；单个 shape 不超过 32 个图元。
]]

local sys   = require "sys"
local exwin = require "exwin"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(1, "音频频谱", function(root)
    local C    = theme.C
    local W, H = theme.W, theme.H

    ----------------------------------------------------------------
    -- 版面常量（1024×600）
    ----------------------------------------------------------------
    local CX, CY   = 512, 278        -- 唱片圆心
    local DISC_D   = 188             -- 唱片直径
    local R_IN     = 106             -- 环形谱线内半径
    local BAR_MAX  = 60              -- 谱线最大长度

    local SIDE_N, SIDE_W, SIDE_STEP, SIDE_BASE = 16, 6, 10, 452
    local SIDE_LX  = 24
    local SIDE_RX  = W - 24 - SIDE_N * SIDE_STEP

    local BX0, BX1, BBASE, BMAX = 190, 834, 452, 118

    local WX0, WX1, WCY, WAMP = 190, 834, 278, 74

    local DOCK_X, DOCK_Y, DOCK_W, DOCK_H = 20, 486, 984, 92
    local PROG_X, PROG_Y, PROG_W = 340, 520, 260
    local PLAY_X, PLAY_Y = 666, 504

    local MAXB = 72                  -- 谱线上限（96 kHz 档）

    ----------------------------------------------------------------
    -- 状态
    ----------------------------------------------------------------
    local S = {
        playing = true,
        live    = true,
        mode    = "ring",
        rate    = 1,                 -- mock.RATES 下标
        bins    = mock.RATES[1].bins,
        stereo  = true,
        band    = nil,               -- nil / "low" / "mid" / "high"
        sel     = -1,                -- 选中的谱线下标（1 基）
        hold    = false,             -- 波形定格
        track   = 1,
        cur     = 102,
        dur     = 198,
        accent  = mock.TRACKS[1].accent, -- 当前歌曲主色（进度条/播放键/中心盘）
        seek_hold = 0,                   -- >0 表示正在拖进度条，暂停自动推进
        sync      = false,               -- 程序设置 slider 值时置位，避免回调把它当成用户拖动
    }

    local T, WT = 0, 0               -- 音频时间 / 波形相位
    local frame = 0
    local val, tgt = {}, {}
    local sideL, sideLt, sideR, sideRt = {}, {}, {}, {}
    local ring_col, bar_col, wave_col, side_col = {}, {}, {}, {}

    local R = { sh_ring = {}, sh_bars = {}, sh_wave = {}, sh_ghost = {},
        band_val = {}, band_fill = {} }
    -- 注：不再有 sh_pulse（见下面创建 shape 处的说明）

    ----------------------------------------------------------------
    -- 防死机两件套（实机踩坑，务必保留）
    --   ① put()：shape 已经有图元/已经清空时不再重复 set_items。
    --      固件里 set_items 无条件 lv_obj_invalidate，哪怕传空表也会把
    --      整个 shape 面积标脏；6 个 shape 全刷 ≈ 每帧重绘整屏，
    --      跑一两分钟 LVGL 堆被高频 malloc/free 打爆 → lv_malloc 返回 NULL
    --      → 固件没判空 → HardFault（ramdump 死机）。
    --   ② set_text()：文字内容没变就不 set_text，省掉矢量字重新栅格化。
    ----------------------------------------------------------------
    local drawn = {}
    local function put(sh, items)
        local has = #items > 0
        if not has and not drawn[sh] then return end
        drawn[sh] = has or nil
        pcall(sh.set_items, sh, items)
    end

    local tstr = {}
    local function set_text(lb, s, key)
        key = key or lb
        if tstr[key] == s then return end
        tstr[key] = s
        pcall(lb.set_text, lb, s)
    end

    ----------------------------------------------------------------
    -- 颜色表（随 bins 变化重建）
    ----------------------------------------------------------------
    local function build_colors()
        local n = S.bins
        -- 亮度取当前主题的 C.lum：深色底用亮一些的谱线（62），
        -- 浅色底必须压到 52 左右，否则粉紫青全是"发白"，在白底上看不见
        local lum = C.lum or 62
        for i = 1, n do
            local ang = (i - 1) / n * 6.2831853 - 1.5707963
            ring_col[i] = theme.hue_col(265 - 76 * (0.5 + 0.5 * math.cos(ang)), 84, lum)
            bar_col[i]  = theme.hue_col(265 - 76 * (i - 1) / math.max(1, n - 1), 84, lum - 1)
        end
        -- 波形折线段最多 64 段，色表按 64 预生成（少了会取到 nil 颜色）
        for i = 1, 64 do
            local k = (i - 1) / 63
            wave_col[i] = theme.hue_col(265 - 90 * k, 85, lum - 1)
        end
        -- 侧柱颜色只跟位置有关，预生成一次，避免每帧 32 次 hue_col
        for i = 1, SIDE_N do
            side_col[i] = theme.hue_col(258 - 40 * (i - 1) / (SIDE_N - 1), 82, lum - 1)
        end
    end

    local function init_vals()
        for i = 1, MAXB do
            val[i] = 0.3
            tgt[i] = 0.3
        end
        for i = 1, SIDE_N do
            sideL[i] = 0.3; sideLt[i] = 0.3
            sideR[i] = 0.3; sideRt[i] = 0.3
        end
        build_colors()
    end
    init_vals()

    ----------------------------------------------------------------
    -- 频段 / 数值
    ----------------------------------------------------------------
    local function band_of(i)
        local k = (i - 0.5) / S.bins
        if k < 1 / 3 then return "low" elseif k < 2 / 3 then return "mid" end
        return "high"
    end

    local function band_dim(i)
        if not S.band then return false end
        return band_of(i) ~= S.band
    end

    -- 切换谱线数量：把当前数值重采样过去，避免柱子突变
    local function set_bins(n)
        if n == S.bins then return end
        local old = S.bins
        local nv, ng = {}, {}
        for i = 1, n do
            local f = (i - 1) / math.max(1, n - 1) * (old - 1)
            local i0 = math.floor(f) + 1
            local i1 = math.min(old, i0 + 1)
            local fr = f - math.floor(f)
            local a0, a1 = val[i0] or 0.3, val[i1] or 0.3
            local b0, b1 = tgt[i0] or 0.3, tgt[i1] or 0.3
            nv[i] = a0 + (a1 - a0) * fr
            ng[i] = b0 + (b1 - b0) * fr
        end
        for i = 1, MAXB do val[i], tgt[i] = nil, nil end
        for i = 1, n do val[i], tgt[i] = nv[i], ng[i] end
        for i = n + 1, MAXB do val[i], tgt[i] = 0.3, 0.3 end
        S.bins = n
        build_colors()
        if R.bins then set_text(R.bins, tostring(n)) end
    end

    ----------------------------------------------------------------
    -- 每帧目标值（多正弦叠加 + 随机抖动，与 html 同款）
    ----------------------------------------------------------------
    local function targets()
        local n = S.bins
        for i = 1, n do
            local a = (i - 1) / n
            local v = 0.50 * (0.5 + 0.5 * math.sin(T * 1.75 + i * 0.38))
            v = v + 0.34 * (0.5 + 0.5 * math.sin(T * 2.85 - i * 0.23))
            v = v + 0.22 * (0.5 + 0.5 * math.sin(T * 4.40 + i * 0.13))
            v = v + 0.14 * (0.5 + 0.5 * math.sin(T * 6.10 - i * 0.51))
            v = v * (0.62 + 0.38 * (math.abs(math.cos(3.1415926 * (a - 0.5))) ^ 0.7))
            -- 抖动从 ±0.05 收到 ±0.035：幅值小了以后，谱线的"毛刺"减少，
            -- 同样帧率下看起来更顺（视觉上的卡顿有一部分是高频抖动造成的）
            v = v + (math.random() - 0.5) * 0.07
            if v < 0.05 then v = 0.05 elseif v > 1 then v = 1 end
            tgt[i] = v
        end
        -- 单声道：左右完全对称
        if not S.stereo then
            local half = math.floor(n / 2)
            for i = 1, half do
                local m = (tgt[i] + tgt[n - i + 1]) * 0.5
                tgt[i] = m
                tgt[n - i + 1] = m
            end
        end
        for i = 1, SIDE_N do
            local k = (i - 1) / (SIDE_N - 1)
            sideLt[i] = math.max(0.06, (0.9 - k * 0.5) *
                (0.45 + 0.55 * math.abs(math.sin(T * (1.4 + k * 2.2) + i * 0.7)))
                + math.random() * 0.12)
            local rv = math.max(0.06, (0.9 - k * 0.5) *
                (0.45 + 0.55 * math.abs(math.sin(T * (1.5 + k * 2.0) - i * 0.6 + 1.2)))
                + math.random() * 0.12)
            sideRt[i] = S.stereo and rv or sideLt[i]
        end
    end

    ----------------------------------------------------------------
    -- 背景光晕
    -- 实机踩坑：大尺寸 container 的 radius 会被固件截断，420/300px 的"圆"实际渲染成
    -- 圆角方块（上一版屏中央出现一块暗方块就是这个），而且大块半透明每帧混合很吃性能。
    -- 结论：大圆一律用 shape 的 circle 图元画，且只保留一层很淡的底光。
    ----------------------------------------------------------------

    ----------------------------------------------------------------
    -- 动态 shape（先建，后面所有交互控件都压在上面）
    -- 每个 shape 只覆盖自己那块区域，避免整屏 canvas 吃内存
    ----------------------------------------------------------------
    local SH_RING  = { x = 320, y = 90,  w = 384, h = 380 }
    local SH_BARS  = { x = 180, y = 314, w = 664, h = 152 }
    local SH_WAVE  = { x = 180, y = 160, w = 664, h = 240 }
    local SH_SIDE  = { x = 12,  y = 316, w = W - 24, h = 152 }

    local SH_DISC  = { x = CX - 100, y = CY - 100, w = 200, h = 200 }

    for i = 1, 3 do
        R.sh_ring[i] = airui.shape({ parent = root, x = SH_RING.x, y = SH_RING.y,
            w = SH_RING.w, h = SH_RING.h, items = {} })
    end
    for i = 1, 3 do
        R.sh_bars[i] = airui.shape({ parent = root, x = SH_BARS.x, y = SH_BARS.y,
            w = SH_BARS.w, h = SH_BARS.h, items = {} })
    end
    for i = 1, 2 do
        R.sh_wave[i] = airui.shape({ parent = root, x = SH_WAVE.x, y = SH_WAVE.y,
            w = SH_WAVE.w, h = SH_WAVE.h, items = {} })
    end
    R.sh_side  = airui.shape({ parent = root, x = SH_SIDE.x, y = SH_SIDE.y,
        w = SH_SIDE.w, h = SH_SIDE.h, items = {} })
    -- 原来这里是"脉冲环"shape：每 2 帧画 3 个半透明 arc。
    -- arc 在固件里是逐行算 mask 再混合（lv_draw_sw_arc），单帧耗时是 rect 的
    -- 十几倍，且只在环形模式出现 → 帧耗时忽高忽低，看着就是环形"一跳一跳"。
    -- 现在扩散环改由唱片 shape 里的静态淡环代替（只重画一次），环形每帧
    -- 的活跟柱状一样：只有一组 set_items。

    ----------------------------------------------------------------
    -- 中心唱片：整块用一个 shape 的 circle 图元画
    -- （大容器圆在实机上 radius 被截断成圆角方块，改用 shape 圆才正确）
    -- 只在模式切换时重建一次，不参与每帧刷新
    ----------------------------------------------------------------
    R.sh_disc = airui.shape({ parent = root, x = SH_DISC.x, y = SH_DISC.y,
        w = SH_DISC.w, h = SH_DISC.h, items = {} })

    -- 波形模式的背景辅助线（html 里那两条淡淡的曲线）。
    -- 放在最后一批创建：既压在唱盘上面，又不会打乱前面 shape 的层级/下标。
    for i = 1, 2 do
        R.sh_ghost[i] = airui.shape({ parent = root, x = SH_WAVE.x, y = SH_WAVE.y,
            w = SH_WAVE.w, h = SH_WAVE.h, items = {} })
    end

    local function draw_disc(a)
        local o = math.floor(255 * a)
        local cx, cy = math.floor(SH_DISC.w / 2), math.floor(SH_DISC.h / 2)
        -- 全部用"实心圆"叠出来，不再用 fill=false 的空心圆：
        -- 空心圆走 lv_draw_sw_arc（逐行算 mask），而实心圆走 rect 快路径。
        -- 因为唱盘每帧都落在环形/柱状/波形的重绘区里，会被反复重绘，
        -- 原来的 1 个空心盘沿 + 3 个脉冲弧就是环形模式卡顿的主因。
        pcall(R.sh_disc.set_items, R.sh_disc, {
            -- 盘沿：实心亮圆 + 内层盘体盖掉中间，只留 3px 亮边
            { type = "circle", cx = cx, cy = cy, r = 94,
              color = C.cyan, width = 1, fill = true,
              fill_color = C.cyan, fill_opacity = math.floor(80 * a) },
            { type = "circle", cx = cx, cy = cy, r = 91,
              color = C.card2, width = 1, fill = true,
              fill_color = C.card2, fill_opacity = o },
            -- 静态同心环（同样用两层实心圆夹出来）
            { type = "circle", cx = cx, cy = cy, r = 82,
              color = C.cyan, width = 1, fill = true,
              fill_color = C.cyan, fill_opacity = math.floor(22 * a) },
            { type = "circle", cx = cx, cy = cy, r = 80,
              color = C.card2, width = 1, fill = true,
              fill_color = C.card2, fill_opacity = o },
            -- 中心封面（跟着当前歌曲配色走）
            { type = "circle", cx = cx, cy = cy, r = 56,
              color = S.accent, width = 1, fill = true,
              fill_color = S.accent, fill_opacity = math.floor(235 * a) },
            -- 中心孔
            { type = "circle", cx = cx, cy = cy, r = 9,
              color = 0x08131F, width = 1, fill = true,
              fill_color = 0x08131F, fill_opacity = o },
        })
    end
    draw_disc(1)

    ----------------------------------------------------------------
    -- 顶栏
    ----------------------------------------------------------------
    theme.box(root, 26, 12, 4, 14, C.purple, 2)
    theme.box(root, 26, 26, 4, 14, C.cyan, 2)
    theme.txt(root, 40, 10, 300, 28, "音频频谱", C.text, 18)

    local r_time = theme.txt(root, 826, 10, 80, 26, "--:--", C.text, 22,
        airui.TEXT_ALIGN_RIGHT)
    local r_date = theme.txt(root, 900, 14, 100, 22, "--/--", C.sub, 16,
        airui.TEXT_ALIGN_RIGHT)

    ----------------------------------------------------------------
    -- 左侧读数
    ----------------------------------------------------------------
    -- 单位和数值放同一行：大三号数字 + 右下角小号 dBFS（原来 dBFS 单独占一行）
    theme.txt(root, 24, 64, 160, 18, "峰值", C.sub, 16)
    R.peak = theme.txt(root, 24, 84, 92, 34, "-6.2", C.cyan2, 30)
    theme.txt(root, 120, 93, 60, 20, "dBFS", C.dim, 16)

    theme.txt(root, 24, 146, 160, 18, "有效值", C.sub, 16)
    R.rms = theme.txt(root, 24, 166, 92, 34, "-18.4", C.cyan2, 30)
    theme.txt(root, 120, 175, 60, 20, "dBFS", C.dim, 16)

    theme.txt(root, 24, 230, 160, 18, "动态范围", C.dim, 16)
    R.dr = theme.txt(root, 24, 250, 160, 26, "12.2 dB", C.purple, 20)

    ----------------------------------------------------------------
    -- 右侧频段 + 采样信息
    ----------------------------------------------------------------
    local band_rows = {}
    for k, b in ipairs(mock.BANDS) do
        local y = 64 + (k - 1) * 30
        theme.txt(root, 840, y, 40, 20, b.name, C.sub, 16)
        theme.box(root, 884, y + 7, 72, 6, C.track, 3)
        R.band_fill[k] = airui.shape({ parent = root, x = 884, y = y + 7,
            w = 72, h = 6, items = {} })
        R.band_val[k] = theme.txt(root, 962, y, 38, 20, "--", C.cyan2, 16,
            airui.TEXT_ALIGN_RIGHT)
        -- 行热区：整行可点（锁定该频段）
        band_rows[k] = theme.hit(root, 838, y - 2, 168, 24, nil)
    end

    theme.txt(root, 840, 158, 160, 18, "频谱线数", C.dim, 16)
    R.bins = theme.txt(root, 840, 176, 160, 24, "44", C.cyan2, 20,
        airui.TEXT_ALIGN_RIGHT)

    theme.txt(root, 840, 204, 160, 18, "采样率", C.dim, 16)
    R.srate = theme.txt(root, 840, 222, 160, 24, "48 000 Hz", C.cyan2, 20,
        airui.TEXT_ALIGN_RIGHT)

    theme.txt(root, 840, 250, 160, 18, "帧率", C.dim, 16)
    R.fps = theme.txt(root, 840, 268, 160, 24, "25 fps", C.cyan2, 20,
        airui.TEXT_ALIGN_RIGHT)

    ----------------------------------------------------------------
    -- 底栏：播放器
    ----------------------------------------------------------------
    theme.box_b(root, DOCK_X, DOCK_Y, DOCK_W, DOCK_H, C.card2, 18, C.line, 1)

    -- 封面：多层圆角方块叠出 html 那种斜向渐变（换歌换配色）
    R.sh_cover = airui.shape({ parent = root, x = 36, y = 502, w = 60, h = 60,
        items = {} })
    local function draw_cover(c1, c2, c3)
        pcall(R.sh_cover.set_items, R.sh_cover, {
            { type = "rect", x = 0,  y = 0,  w = 60, h = 60, radius = 14,
              color = c1, width = 1, fill = true, fill_color = c1, fill_opacity = 255 },
            { type = "rect", x = 4,  y = 4,  w = 52, h = 52, radius = 13,
              color = c2, width = 1, fill = true, fill_color = c2, fill_opacity = 235 },
            { type = "rect", x = 11, y = 11, w = 38, h = 38, radius = 11,
              color = c3, width = 1, fill = true, fill_color = c3, fill_opacity = 210 },
            { type = "circle", cx = 30, cy = 30, r = 7, color = 0x0A1420, width = 1,
              fill = true, fill_color = 0x0A1420, fill_opacity = 255 },
        })
    end
    draw_cover(mock.TRACKS[1].c1, mock.TRACKS[1].c2, mock.TRACKS[1].c3)

    R.ttl = theme.txt(root, 108, 506, 220, 24, "--", C.text, 20)
    R.art = theme.txt(root, 108, 532, 220, 20, "--", C.sub, 16)

    -- 进度条轨道 + 进度 shape + 旋钮
    theme.box(root, PROG_X, PROG_Y, PROG_W, 8, C.track, 4)
    R.sh_prog = airui.shape({ parent = root, x = PROG_X, y = PROG_Y,
        w = PROG_W, h = 8, items = {} })
    R.knob = theme.circle(root, PROG_X - 7, PROG_Y - 3, 14, C.knob, 255)

    R.cur = theme.txt(root, PROG_X, 532, 60, 18, "00:00", C.sub, 16)
    R.dur = theme.txt(root, PROG_X + PROG_W - 60, 532, 60, 18, "00:00", C.sub, 16,
        airui.TEXT_ALIGN_RIGHT)

    -- 上一首 / 播放 / 下一首
    local function ctrl_btn(x, y, d)
        theme.box_b(root, x, y, d, d, C.card, math.floor(d / 2), C.line, 1)
        return airui.shape({ parent = root, x = x, y = y, w = d, h = d, items = {} })
    end
    local sh_prev = ctrl_btn(616, 512, 40)
    local sh_next = ctrl_btn(732, 512, 40)
    R.play_bg = theme.box(root, PLAY_X, PLAY_Y, 56, 56, S.accent, 28)
    local sh_picon = airui.shape({ parent = root, x = PLAY_X, y = PLAY_Y,
        w = 56, h = 56, items = {} })

    local ICON = C.icon
    pcall(sh_prev.set_items, sh_prev, {
        { type = "rect", x = 12, y = 12, w = 3, h = 16, radius = 1,
          color = ICON, width = 1, fill = true, fill_color = ICON, fill_opacity = 255 },
        { type = "line", x1 = 28, y1 = 12, x2 = 17, y2 = 20,
          color = ICON, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = 17, y1 = 20, x2 = 28, y2 = 28,
          color = ICON, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = 28, y1 = 28, x2 = 28, y2 = 12,
          color = ICON, width = 3, round_start = true, round_end = true },
    })
    pcall(sh_next.set_items, sh_next, {
        { type = "rect", x = 25, y = 12, w = 3, h = 16, radius = 1,
          color = ICON, width = 1, fill = true, fill_color = ICON, fill_opacity = 255 },
        { type = "line", x1 = 12, y1 = 12, x2 = 23, y2 = 20,
          color = ICON, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = 23, y1 = 20, x2 = 12, y2 = 28,
          color = ICON, width = 3, round_start = true, round_end = true },
        { type = "line", x1 = 12, y1 = 28, x2 = 12, y2 = 12,
          color = ICON, width = 3, round_start = true, round_end = true },
    })

    local ICON_DARK = 0x08131F
    local function icon_pause()
        return {
            { type = "rect", x = 16, y = 16, w = 8, h = 24, radius = 2,
              color = ICON_DARK, width = 1, fill = true,
              fill_color = ICON_DARK, fill_opacity = 255 },
            { type = "rect", x = 32, y = 16, w = 8, h = 24, radius = 2,
              color = ICON_DARK, width = 1, fill = true,
              fill_color = ICON_DARK, fill_opacity = 255 },
        }
    end
    local function icon_play()
        return {
            { type = "line", x1 = 20, y1 = 17, x2 = 40, y2 = 28,
              color = ICON_DARK, width = 5, round_start = true, round_end = true },
            { type = "line", x1 = 40, y1 = 28, x2 = 20, y2 = 39,
              color = ICON_DARK, width = 5, round_start = true, round_end = true },
            { type = "line", x1 = 20, y1 = 39, x2 = 20, y2 = 17,
              color = ICON_DARK, width = 5, round_start = true, round_end = true },
        }
    end

    ----------------------------------------------------------------
    -- 三种模式按钮
    ----------------------------------------------------------------
    local mode_pill = {}
    local set_mode                       -- 前置声明（按钮闭包要用）

    local MODES = {
        { key = "ring", name = "环形" },
        { key = "bars", name = "柱状" },
        { key = "wave", name = "波形" },
    }
    for i, m in ipairs(MODES) do
        local x = 792 + (i - 1) * 68
        mode_pill[m.key] = theme.pill(root, x, 514, 62, 34, m.name, 16, 9,
            function() set_mode(m.key) end)
    end

    ----------------------------------------------------------------
    -- 提示条（顶部居中，2 秒自动消失）
    ----------------------------------------------------------------
    -- 有 border_width 的容器，内容区比外框左右各窄 1px。里面的 label 若仍按 320 撑满，
    -- 就会溢出 2px → LVGL 认为内容超宽 → 底部弹出一条灰色横向滚动条（就是"下划线"）。
    -- 所以这里左右各让 2px（316 宽）。
    local hint_box = airui.container({ parent = root, x = 352, y = 54, w = 320, h = 30,
        color = C.deep, color_opacity = 235, radius = 15,
        border_color = C.cyan, border_width = 1 })
    local hint_lb = theme.txt(hint_box, 2, 0, 316, 30, "", C.cyan2, 16,
        airui.TEXT_ALIGN_CENTER)
    pcall(hint_box.set_hidden, hint_box, true)

    local hint_until = 0
    local function hint(msg)
        set_text(hint_lb, msg)
        pcall(hint_box.set_hidden, hint_box, false)
        hint_until = frame + 62          -- 32ms × 62 ≈ 2 秒
    end

    ----------------------------------------------------------------
    -- 冻结卡片（LIVE 关闭时盖在中间，提示整体已定格）
    ----------------------------------------------------------------
    local fz_card = airui.container({ parent = root, x = 352, y = 96, w = 320, h = 82,
        color = 0x06101A, color_opacity = 240, radius = 16,
        border_color = C.cyan, border_width = 1 })
    airui.shape({ parent = fz_card, x = 22, y = 26, w = 24, h = 30, items = {
        { type = "rect", x = 2, y = 0, w = 7, h = 30, radius = 2,
          color = C.cyan2, width = 1, fill = true, fill_color = C.cyan2, fill_opacity = 255 },
        { type = "rect", x = 15, y = 0, w = 7, h = 30, radius = 2,
          color = C.cyan2, width = 1, fill = true, fill_color = C.cyan2, fill_opacity = 255 },
    } })
    theme.txt(fz_card, 62, 16, 240, 26, "已冻结", C.text, 22)
    theme.txt(fz_card, 62, 44, 240, 20, "实时已关闭 · 点「实时」恢复", C.sub, 16)
    pcall(fz_card.set_hidden, fz_card, true)

    ----------------------------------------------------------------
    -- 绘制：环形
    ----------------------------------------------------------------
    local function draw_ring()
        local ox, oy = SH_RING.x, SH_RING.y
        local n = S.bins
        local gs = { {}, {}, {} }
        local gi = 1
        for i = 1, n do
            local ang = (i - 1) / n * 6.2831853 - 1.5707963
            local ca, sa = math.cos(ang), math.sin(ang)
            local len = 14 + (val[i] or 0.3) * BAR_MAX
            local r1 = R_IN + len
            local x1 = math.floor(CX + ca * R_IN + 0.5) - ox
            local y1 = math.floor(CY + sa * R_IN + 0.5) - oy
            local x2 = math.floor(CX + ca * r1 + 0.5) - ox
            local y2 = math.floor(CY + sa * r1 + 0.5) - oy
            local sel = (i == S.sel)
            -- 线宽 6→5、去掉两端圆头：斜线在固件里是"逐行算 mask 再混合"，
            -- 宽度直接决定 mask 行数，圆头还要额外画两个小圆。
            -- 44 根 × 2 个圆头 = 每帧省 88 次填充，肉眼看不出差别。
            gs[gi][#gs[gi] + 1] = {
                type = "line", x1 = x1, y1 = y1, x2 = x2, y2 = y2,
                color = sel and C.sel or ring_col[i],
                width = sel and 8 or 5,
                opacity = band_dim(i) and 60 or 255,
            }
            if #gs[gi] >= 32 and gi < 3 then gi = gi + 1 end
        end
        for k = 1, 3 do put(R.sh_ring[k], gs[k]) end
    end

    ----------------------------------------------------------------
    -- 绘制：柱状
    ----------------------------------------------------------------
    local function draw_bars()
        local ox, oy = SH_BARS.x, SH_BARS.y
        local n = S.bins
        local pitch = (BX1 - BX0) / n
        local bw = math.floor(math.min(9, pitch * 0.58))
        if bw < 3 then bw = 3 end
        local gs = { {}, {}, {} }
        local gi = 1
        for i = 1, n do
            local h = math.floor(16 + (val[i] or 0.3) * BMAX)
            local x = math.floor(BX0 + (i - 1) * pitch + (pitch - bw) / 2 + 0.5) - ox
            local sel = (i == S.sel)
            gs[gi][#gs[gi] + 1] = {
                type = "rect", x = x, y = BBASE - h - oy, w = bw, h = h, radius = 2,
                color = sel and C.sel or bar_col[i],
                width = 1, fill = true,
                fill_color = sel and C.sel or bar_col[i],
                fill_opacity = band_dim(i) and 60 or 255,
            }
            if #gs[gi] >= 32 and gi < 3 then gi = gi + 1 end
        end
        for k = 1, 3 do put(R.sh_bars[k], gs[k]) end
    end

    ----------------------------------------------------------------
    -- 绘制：波形
    ----------------------------------------------------------------
    local function sample(k)                 -- k: 0~1
        local n = S.bins
        local f = k * (n - 1)
        local i0 = math.floor(f) + 1
        local i1 = math.min(n, i0 + 1)
        local fr = f - math.floor(f)
        local a0, a1 = val[i0] or 0.3, val[i1] or 0.3
        return a0 + (a1 - a0) * fr
    end

    local function draw_wave()
        local ox, oy = SH_WAVE.x, SH_WAVE.y
        -- 31 段折线（每段 ~21px，线宽 3）就够平滑了；从 63 段一路降下来，
        -- 波形模式的斜线数量砍掉一半，帧耗时才能压在 40ms 以内。
        -- 最高次谐波同步降到 37.7，否则点数少了高频项会变成锯齿。
        local P = 32
        local gs = { {}, {} }
        local gi = 1
        local px, py
        for i = 0, P - 1 do
            local k = i / (P - 1)
            local x = WX0 + (WX1 - WX0) * k
            local y = 0.55 * math.sin(k * 12.56637 + WT * 2.1)
                + 0.28 * math.sin(k * 25.13274 - WT * 1.4)
                + 0.11 * math.sin(k * 37.69911 + WT * 3.2)
            -- 包络两端不再压到 0.3：原来右端（高频侧）几乎贴着中线，
            -- 看起来就像"后面几根线没了"。0.48 起步，首尾都有可见的摆幅。
            local env = 0.48 + 0.52 * math.sin(3.1415926 * k)
            local v = y * env * (0.35 + 1.15 * sample(k))
            local sx = math.floor(x + 0.5) - ox
            local sy = math.floor(WCY - v * WAMP + 0.5) - oy
            if i > 0 then
                -- 段数少了，颜色仍要铺满"紫→青"整个渐变，按段号比例取色
                local ci = math.floor((i - 1) / (P - 2) * 63) + 1
                gs[gi][#gs[gi] + 1] = {
                    type = "line", x1 = px, y1 = py, x2 = sx, y2 = sy,
                    color = wave_col[ci], width = 3,
                    opacity = S.hold and 150 or 255,
                    round_start = true, round_end = true,
                }
                if #gs[gi] >= 32 and gi < 2 then gi = 2 end
            end
            px, py = sx, sy
        end
        for k = 1, 2 do put(R.sh_wave[k], gs[k]) end

        -- 两条背景辅助曲线（html 里那两条淡线）：单色细线 + 低透明度。
        -- 18 段、1px、不画圆头（圆头对 1px 线看不出，白费两次填充）
        for w = 1, 2 do
            local items = {}
            local amp = (w == 1) and 0.62 or 0.40
            local ph  = (w == 1) and 1.1 or -1.9
            local col = (w == 1) and C.ghost1 or C.ghost2
            local opa = (w == 1) and 140 or 115
            local NAP = 14
            local ppx, ppy
            for i = 0, NAP - 1 do
                local k = i / (NAP - 1)
                local x = WX0 + (WX1 - WX0) * k
                local y = amp * math.sin(k * 9.42478 + WT * 1.15 + ph)
                    + 0.24 * math.sin(k * 21.99115 - WT * 0.85 + ph)
                local env = 0.50 + 0.50 * math.sin(3.1415926 * k)
                local sx = math.floor(x + 0.5) - ox
                local sy = math.floor(WCY - y * env * WAMP * 0.8 + 0.5) - oy
                if i > 0 then
                    items[#items + 1] = {
                        type = "line", x1 = ppx, y1 = ppy, x2 = sx, y2 = sy,
                        color = col, width = 1, opacity = opa,
                    }
                end
                ppx, ppy = sx, sy
            end
            put(R.sh_ghost[w], items)
        end
    end

    ----------------------------------------------------------------
    -- 绘制：左右侧柱
    ----------------------------------------------------------------
    local function draw_side()
        local ox, oy = SH_SIDE.x, SH_SIDE.y
        local items = {}
        for i = 1, SIDE_N do
            local col = side_col[i]
            local lh = math.floor(18 + (sideL[i] or 0.3) * 96)
            items[#items + 1] = {
                type = "rect", x = SIDE_LX + (i - 1) * SIDE_STEP - ox,
                y = SIDE_BASE - lh - oy, w = SIDE_W, h = lh, radius = 3,
                color = col, width = 1, fill = true, fill_color = col,
                fill_opacity = 235,
            }
            local rh = math.floor(18 + (sideR[i] or 0.3) * 96)
            items[#items + 1] = {
                type = "rect", x = SIDE_RX + (i - 1) * SIDE_STEP - ox,
                y = SIDE_BASE - rh - oy, w = SIDE_W, h = rh, radius = 3,
                color = col, width = 1, fill = true, fill_color = col,
                fill_opacity = 235,
            }
        end
        put(R.sh_side, items)
    end

    ----------------------------------------------------------------
    -- 绘制：进度条
    ----------------------------------------------------------------
    local prog_w, prog_sec = -1, -1

    -- 只画进度条本身（填充 + 旋钮 + 读数），拖动时用，不碰 slider
    local function paint_prog()
        local p = (S.dur > 0) and (S.cur / S.dur) or 0
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        local w = math.floor(PROG_W * p)
        if w < 4 then w = 4 end
        if w ~= prog_w then
            prog_w = w
            put(R.sh_prog, {
                { type = "rect", x = 0, y = 0, w = w, h = 8, radius = 4,
                  color = S.accent, width = 1, fill = true,
                  fill_color = S.accent, fill_opacity = 255 },
            })
        end
        pcall(R.knob.set_pos, R.knob, PROG_X + w - 7, PROG_Y - 3)
        set_text(R.cur, theme.fmt_time(S.cur))
        prog_sec = math.floor(S.cur)
    end

    local function draw_prog(force)
        -- 进度条 1 秒才动 1 px 左右，宽度和秒数都没变就别刷（每次刷都要重绘 + 移动旋钮）
        local p = (S.dur > 0) and (S.cur / S.dur) or 0
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        local w = math.floor(PROG_W * p)
        if w < 4 then w = 4 end
        local sec = math.floor(S.cur)
        if not force and w == prog_w and sec == prog_sec then return end
        paint_prog()
        -- 同步给可拖动的 slider（它是透明的，只负责收手指）。
        -- 拖动中不要回写：手指正在拖的时候 set_value 会跟 LVGL 抢值，
        -- 波形会来回跳一下（看着就是卡顿）。
        if R.slider and S.seek_hold == 0 then
            S.sync = true
            pcall(R.slider.set_value, R.slider, math.floor(S.cur), false)
            S.sync = false
        end
    end

    ----------------------------------------------------------------
    -- 播放 / 暂停
    ----------------------------------------------------------------
    local function set_playing(v)
        S.playing = v
        pcall(sh_picon.set_items, sh_picon, v and icon_pause() or icon_play())

    end

    ----------------------------------------------------------------
    -- 选中 / 提示
    ----------------------------------------------------------------
    local function toggle_sel(idx)
        if S.sel == idx then
            S.sel = -1
            hint("已取消选择")
        else
            S.sel = idx
            hint(string.format("频段 #%02d · %s · %d%%",
                idx, mock.freq_text(idx, S.bins), math.floor((val[idx] or 0) * 100)))
        end
    end

    local function toggle_band(key)
        if S.band == key then
            S.band = nil
        else
            S.band = key
        end
        for k, b in ipairs(mock.BANDS) do
            -- 行热区本身没有视觉，靠帧里的文字/进度条颜色反映；这里只做提示
            if b.key == S.band then
                hint(b.name .. "已锁定 · 其余频段变暗")
            end
        end
        if not S.band then hint("已取消频段锁定") end
    end

    ----------------------------------------------------------------
    -- 模式切换 + 热区显隐
    ----------------------------------------------------------------
    local ring_zones, bars_zones, wave_zone, disc_zone = {}, {}, nil, nil

    local function sync_zones()
        local ring_on = (S.mode == "ring")
        local bars_on = (S.mode == "bars")
        local wave_on = (S.mode == "wave")
        for i = 1, #ring_zones do
            pcall(ring_zones[i].set_hidden, ring_zones[i], not ring_on)
        end
        for i = 1, #bars_zones do
            pcall(bars_zones[i].set_hidden, bars_zones[i], not bars_on)
        end
        pcall(wave_zone.set_hidden, wave_zone, not wave_on)
        pcall(disc_zone.set_hidden, disc_zone, wave_on)
    end

    set_mode = function(m)
        if S.mode == m then return end
        S.mode = m
        S.sel = -1
        for k, p in pairs(mode_pill) do
            if k == m then theme.pill_on(p) else theme.pill_off(p) end
        end
        draw_disc(m == "ring" and 1 or 0.3)
        sync_zones()
        -- 三个 shape 都要清空，只清第一个会留下残影（旧柱子还在屏幕上）
        if m ~= "ring" then
            for k = 1, 3 do put(R.sh_ring[k], {}) end
        end
        if m ~= "bars" then
            for k = 1, 3 do put(R.sh_bars[k], {}) end
        end
        if m ~= "wave" then
            for k = 1, 2 do put(R.sh_wave[k], {}) end
            for k = 1, 2 do put(R.sh_ghost[k], {}) end
        end
        hint(({ ring = "环形频谱", bars = "柱状频谱", wave = "波形频谱" })[m])
    end
    theme.pill_on(mode_pill.ring)

    ----------------------------------------------------------------
    -- 顶部 chips
    ----------------------------------------------------------------
    local c_live, c_rate, c_ch

    c_live = theme.pill(root, 372, 12, 80, 28, "实时", 16, 14, function()
        S.live = not S.live
        set_text(c_live.lb, S.live and "实时" or "已冻结")
        if S.live then
            theme.pill_on(c_live)
            pcall(fz_card.set_hidden, fz_card, true)
            hint("实时开启 · 刷新中")
        else
            theme.pill_off(c_live)
            pcall(fz_card.set_hidden, fz_card, false)
            hint("实时已关闭 · 频谱冻结")
        end
    end)

    c_rate = theme.pill(root, 460, 12, 88, 28, mock.RATES[1].label, 16, 14, function()
        S.rate = S.rate % #mock.RATES + 1
        local r = mock.RATES[S.rate]
        set_text(c_rate.lb, r.label)
        set_bins(r.bins)
        S.sel = -1
        -- 千位分隔必须按"千位"算：之前用 gsub 匹配 4 位数字，
        -- 96000 会被切成 "9 6000"。这里直接 %d + %03d。
        local hz_s = string.format("%d %03d Hz",
            math.floor(r.hz / 1000), r.hz % 1000)
        set_text(R.srate, hz_s)
        hint(string.format("采样率 %s · %d 根谱线", r.label, r.bins))
    end)

    -- 深浅主题切换（照搬其他工程约定：切完必须 rerender，且要延迟到事件外）
    theme.pill(root, 664, 12, 96, 28,
        (theme.cur == "dark") and "深色" or "浅色", 16, 14, function()
        theme.toggle_theme()
        sys.timerStart(function() theme.rerender_page() end, 30)
    end)

    c_ch = theme.pill(root, 556, 12, 92, 28, "立体声", 16, 14, function()
        S.stereo = not S.stereo
        set_text(c_ch.lb, S.stereo and "立体声" or "单声道")
        if S.stereo then theme.pill_off(c_ch) else theme.pill_on(c_ch) end
        hint(S.stereo and "立体声 · 左右独立" or "单声道 · 频谱左右对称")
    end)
    theme.pill_on(c_live)

    ----------------------------------------------------------------
    -- 底栏按钮
    ----------------------------------------------------------------
    local function load_track(idx)
        local n = #mock.TRACKS
        S.track = ((idx - 1) % n) + 1
        local tr = mock.TRACKS[S.track]
        S.dur = tr.dur
        S.cur = 0
        set_text(R.ttl, tr.name)
        set_text(R.art, tr.artist)
        set_text(R.dur, theme.fmt_time(tr.dur))
        -- 换歌换配色：封面 / 进度条 / 播放键 / 中心盘一起变，全部取同一个 accent
        S.accent = tr.accent
        draw_cover(tr.c1, tr.c2, tr.c3)
        pcall(R.play_bg.set_color, R.play_bg, tr.accent, 255)
        draw_disc(S.mode == "ring" and 1 or 0.3)
        -- 拖动条的量程跟着歌长走（否则拖到底只能到上一首的长度）
        if R.slider then pcall(R.slider.set_range, R.slider, 0, math.floor(S.dur)) end
        draw_prog(true)
        -- 不要用 ▶ / ❚❚ 这类字符：hzfont 缺字形，实机会渲染成方框
        hint(tr.name)
    end

    local function seek_ratio(p)
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        S.cur = math.floor(S.dur * p)
        draw_prog(true)
        hint("跳转到 " .. theme.fmt_time(S.cur))
    end

    ----------------------------------------------------------------
    -- 热区：环形 16 段 / 柱状 12 段 / 波形 1 块 / 唱片 1 块
    ----------------------------------------------------------------
    local RZ_N, BZN = 16, 12
    local rr = R_IN + 34
    for i = 0, RZ_N - 1 do
        local ang = (i + 0.5) / RZ_N * 6.2831853 - 1.5707963
        local zx = math.floor(CX + math.cos(ang) * rr - 22 + 0.5)
        local zy = math.floor(CY + math.sin(ang) * rr - 22 + 0.5)
        ring_zones[i + 1] = theme.hit(root, zx, zy, 44, 44, function()
            local idx = math.floor(i * S.bins / RZ_N) + 1
            if idx > S.bins then idx = S.bins end
            toggle_sel(idx)
        end)
    end

    local bw_zone = math.floor((BX1 - BX0) / BZN)
    for j = 0, BZN - 1 do
        bars_zones[j + 1] = theme.hit(root, BX0 + j * bw_zone, 336,
            bw_zone, 118, function()
                local idx = math.floor(j * S.bins / BZN) + 1
                if idx > S.bins then idx = S.bins end
                toggle_sel(idx)
            end)
    end

    wave_zone = theme.hit(root, WX0 - 10, WCY - WAMP - 16,
        (WX1 - WX0) + 20, WAMP * 2 + 32, function()
            S.hold = not S.hold
            hint(S.hold and "波形已保持" or "波形实时刷新")
        end)

    disc_zone = theme.hit(root, CX - 62, CY - 62, 124, 124, function()
        set_playing(not S.playing)
        hint(S.playing and "播放" or "暂停")
    end)

    -- 右侧频段行
    for k, b in ipairs(mock.BANDS) do
        pcall(band_rows[k].set_on_click, band_rows[k], function() toggle_band(b.key) end)
    end

    -- 左右侧柱：横向前 1/3 / 中 1/3 / 后 1/3 分别对应 LOW / MID / HIGH
    local side_w = SIDE_N * SIDE_STEP
    local third  = math.floor(side_w / 3)
    for s = 0, 2 do
        local bk = mock.BANDS[s + 1].key
        theme.hit(root, SIDE_LX - 4 + s * third, SIDE_BASE - 130,
            third, 140, function() toggle_band(bk) end)
        theme.hit(root, SIDE_RX - 4 + s * third, SIDE_BASE - 130,
            third, 140, function() toggle_band(bk) end)
    end

    -- 底栏
    theme.hit(root, 36, 502, 60, 60, function()
        set_playing(not S.playing)
        hint(S.playing and "播放" or "暂停")
    end)
    theme.hit(root, 616, 512, 40, 40, function() load_track(S.track - 1) end)
    theme.hit(root, PLAY_X, PLAY_Y, 56, 56, function()
        set_playing(not S.playing)
        hint(S.playing and "播放" or "暂停")
    end)
    theme.hit(root, 732, 512, 40, 40, function() load_track(S.track + 1) end)

    -- 进度条：10 段热区（无坐标点击 API，只能分段近似）
    local SEEK_N = 10
    for j = 0, SEEK_N - 1 do
        local seg = math.floor(PROG_W / SEEK_N)
        theme.hit(root, PROG_X + j * seg, PROG_Y - 8, seg, 24, function()
            seek_ratio((j + 0.5) / SEEK_N)
        end)
    end

    -- 进度条拖动：原生 slider 透明覆盖在进度条上（三个 part 全透明），
    -- 真正看到的仍是 shape + 旋钮，slider 只负责接收"按下-滑动-抬起"。
    -- 放在上面这排热区之后创建 = 层级更高，拖动不会被点按热区抢走。
    -- 没有 slider 的固件自动退回后面的 10 段点按热区。
    if airui.slider then
        local ok_sl, sl = pcall(airui.slider, {
            parent = root,
            x = PROG_X - 12, y = PROG_Y - 10, w = PROG_W + 24, h = 28,
            min = 0, max = math.floor(S.dur), value = math.floor(S.cur),
            style = { bg_opa = 0, indicator_opa = 0, knob_opa = 0,
                      border_width = 0, radius = 14, pad = 0 },
            on_change = function(self, v)
                if S.sync then return end           -- 程序同步触发的，忽略
                v = tonumber(v)
                if not v and R.slider then pcall(function() v = R.slider:get_value() end) end
                if not v then return end
                if v < 0 then v = 0 elseif v > S.dur then v = S.dur end
                if v == S.cur then return end       -- 同一个像素内的重复事件直接丢掉
                S.cur = v
                S.seek_hold = 24                    -- 拖动期间暂停自动推进
                paint_prog()                        -- 立即重绘：等下一帧会差 1~2 帧，手感发黏
            end,
        })
        if ok_sl and sl then R.slider = sl end
    end

    sync_zones()

    ----------------------------------------------------------------
    -- HUD 刷新
    ----------------------------------------------------------------
    local last_band = nil
    local band_w = { -1, -1, -1 }

    local function upd_hud()
        local n = S.bins
        local sum, mx = 0, 0
        for i = 1, n do
            local v = val[i] or 0
            sum = sum + v
            if v > mx then mx = v end
        end
        local avg = sum / math.max(1, n)

        set_text(R.peak, string.format("%.1f", -30 + mx * 26))
        set_text(R.rms, string.format("%.1f", -42 + avg * 24))
        set_text(R.dr, string.format("%.1f dB", 12 + mx * 6))

        local low  = math.min(99, math.floor(18 + avg * 120))
        local mid  = math.min(99, math.floor(12 + math.abs(math.sin(T * 0.7)) * 105))
        local high = math.min(99, math.floor(10 + math.abs(math.cos(T * 0.9)) * 88))
        local vals = { low, mid, high }
        for k = 1, 3 do
            set_text(R.band_val[k], tostring(vals[k]))
            local w = math.max(2, math.floor(72 * vals[k] / 99))
            -- 条宽没变就不重画（否则每 8 帧固定把 3 个小 shape 标脏）
            if w ~= band_w[k] then
                band_w[k] = w
                local col = (S.band == mock.BANDS[k].key) and C.cyan2 or C.cyan
                put(R.band_fill[k], {
                    { type = "rect", x = 0, y = 0, w = w, h = 6, radius = 3,
                      color = col, width = 1, fill = true,
                      fill_color = col, fill_opacity = 255 },
                })
            end
        end

        -- 频段锁定态：文字变亮（只在锁定状态真的变了时才刷）
        if S.band ~= last_band then
            last_band = S.band
            for k, b in ipairs(mock.BANDS) do
                local on = (S.band == b.key)
                pcall(R.band_val[k].set_color, R.band_val[k],
                    on and C.strong or C.cyan2, 255)
                band_w[k] = -1          -- 颜色变了，进度条要跟着重画一次
            end
        end
    end

    local function upd_clock()
        pcall(function()
            local t = os.date("*t")
            if t then
                set_text(r_time, string.format("%02d:%02d", t.hour, t.min))
                local wd = ({ "日", "一", "二", "三", "四", "五", "六" })[t.wday] or ""
                set_text(r_date, string.format("%02d/%02d 周%s", t.month, t.day, wd))
            end
        end)
    end

    ----------------------------------------------------------------
    -- 内存观测：每 ~5 秒打一行，万一下次还死机，日志里能看出是
    -- Lua 堆在涨（脚本泄漏）还是系统堆被画图吃光（渲染压力）
    ----------------------------------------------------------------
    local function log_mem()
        pcall(function()
            local kb = collectgarbage("count")
            local extra = ""
            local ok, total, used, peak = pcall(rtos.meminfo, "sys")
            if ok and total then
                extra = string.format(" sys %d/%d/%d", used or 0, total or 0, peak or 0)
            end
            log.info("spectrum", "mem", string.format("lua %.1fKB%s", kb, extra))
        end)
    end

    ----------------------------------------------------------------
    -- 主循环（跑完一帧再 wait 32ms，目标 25fps 以上）
    -- 实机性能要点（"流畅优先"，视觉上只做肉眼看不出的削减）：
    --   ① 谱线/波形每帧只调一次 set_items，空 shape 一律跳过；
    --   ② 侧柱变化慢，每 3 帧才重绘（省掉 2/3 的 32 个 rect）；
    --   ③ HUD 文字（矢量字要重新栅格化）每 10 帧才刷一次；
    --   ④ 平滑用"快升慢降"，抖动幅值收到 ±0.035，线条不再来回毛刺；
    --   ⑤ 环形：线宽 6→5、去圆头，每帧省 88 次小圆填充；
    --      唱盘全部改实心圆叠色，一个 arc 都不画（arc 是逐行算 mask 的）；
    --   ⑥ 波形：折线 63→31 段，淡线 22→14 段；
    --   ⑦ 帧间隔 32ms：由 theme.make_page 的 taskInit 循环节流，
    --      跑完本帧才开始计时，不会像 timerLoopStart 那样积压事件。
    --   帧耗时均匀 + 单帧成本低 = 看着顺。
    ----------------------------------------------------------------
    local DT  = 0.032               -- 每帧推进的"音频时间"
    local RUN = 1.35                -- 节奏倍率：三种模式的动画速度（快一点更活）

    local function update()
        frame = frame + 1

        -- 采样率同时影响跳动速度（与 html 的 spd = rate/48 一致）：
        -- 96kHz 是 48kHz 的两倍速，切档时除了谱线数量，运动节奏也跟着变
        -- RUN ×1.35：整体节奏再快一点（三种模式共用同一个时间基准）
        local spd = mock.RATES[S.rate].hz / 48000
        if S.playing then T = T + DT * spd * RUN end
        if S.playing and S.live and not S.hold then WT = WT + DT * spd * RUN end

        if S.live then
            targets()
            -- 快升慢降：上升跟 0.55×1.15、下降只跟 0.55×0.75。
            -- 真实频谱就是这个手感，而且回落的线条不会来回抖，看着更顺。
            local k = S.playing and 0.55 or 0.06
            local up, dn = k * 1.15, k * 0.75
            for i = 1, S.bins do
                local d = tgt[i] - val[i]
                val[i] = val[i] + d * (d > 0 and up or dn)
            end
            for i = 1, SIDE_N do
                sideL[i] = sideL[i] + (sideLt[i] - sideL[i]) * 0.38
                sideR[i] = sideR[i] + (sideRt[i] - sideR[i]) * 0.38
            end
        end

        -- 冻结时降频重绘（数值本来就不变，省 CPU）
        if S.live or (frame % 10 == 0) then
            if S.mode == "ring" then draw_ring()
            elseif S.mode == "bars" then draw_bars()
            else draw_wave() end
            -- 侧柱是装饰，8fps 足够；省下来的时间全留给主图
            if frame % 3 == 0 then draw_side() end
        end

        -- HUD 文字要重新栅格化，10 帧（0.4s）一次够用
        if frame % 10 == 0 then
            upd_hud()
        end

        -- 拖动进度条时（seek_hold > 0）暂停自动推进，手指抬起后 24 帧恢复
        if S.seek_hold > 0 then S.seek_hold = S.seek_hold - 1 end

        if frame % 5 == 0 then
            if S.seek_hold == 0 and S.playing then
                S.cur = S.cur + DT * 5
                if S.cur > S.dur then S.cur = 0 end
            end
            draw_prog()
        end

        if frame % 20 == 0 then upd_clock() end
        if frame % 80 == 0 then log_mem() end

        if hint_until > 0 and frame > hint_until then
            hint_until = 0
            pcall(hint_box.set_hidden, hint_box, true)
        end
    end

    ----------------------------------------------------------------
    -- 首帧
    ----------------------------------------------------------------
    set_playing(true)
    set_text(R.ttl, mock.TRACKS[1].name)
    set_text(R.art, mock.TRACKS[1].artist)
    set_text(R.dur, theme.fmt_time(mock.TRACKS[1].dur))
    S.dur = mock.TRACKS[1].dur
    set_text(R.srate, "48 000 Hz")
    set_text(R.bins, tostring(S.bins))
    upd_clock()

    return update, 32
end)
