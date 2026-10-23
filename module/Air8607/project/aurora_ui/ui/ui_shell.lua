--[[
@module  ui_shell
@summary AURORA UI - 外壳（极光背景 / HUD / 玻璃卡片 / Dock / 页面滑动过渡 / 主循环）
@version 1.0
@date    2026.10.22
@author  江访

=== 整屏结构（1024x600）===
  root 容器（不透明底色）
   ├─ stage 视口 (16,76,992,438)  透明、裁剪子对象
   │   ├─ bg 极光层     （全舞台 shape，10fps 重算）
   │   ├─ page[i] 页面容器（懒加载，透明，内部分 HERO 主视觉 + PANEL 卡片）
   ├─ HUD 顶栏 (0,0,1024,76)      品牌 / 页面标题 / 时钟 / FPS
   ├─ DOCK (16,524,992,62)        4 个页签 + 弹簧滑动指示器
   └─ sweep 过渡光带              只在页面切换时出现

=== 三个关键决策 ===
1、z 序：stage 先建、HUD/DOCK 后建。LVGL 后建者在上，这样即使某些固件版本
   不裁剪子对象，页面滑动溢出也会被 HUD/DOCK 的不透明底盖住，不会露出破绽。
2、页面懒加载 + 只隐藏不销毁：与 airui_showcase 一致，避免反复创建/销毁 LVGL 对象；
   首次切到某页才付构建开销。
3、时间基准用 mcu.ticks() 并经 mcu.hz() 折算：tick 单位依平台而变
   （PC 模拟器 1ms/tick，Air8607 主控约 20ms/tick），直接当毫秒会让动画慢 20 倍。
   动画步长则用固定 FRAME_MS：tick 分辨率(20ms)比帧间隔(33ms)粗，
   拿 tick 差当 dt 会得到 20/40ms 的抖动值，画面一顿一顿。
]]
local fx = require "fx"
local T = require "theme"

local VIEWS = {
    require "view_nexus",
    require "view_spectrum",
    require "view_orbit",
    require "view_stardust",
}

local M = {}

local C = T.c
local SW, SH = T.screen.w, T.screen.h

-- ==================== 运行时状态 ====================
local root, stage, hud, dock
local bgShape, gridShape, sweep
local pageObj, pageBuilt = {}, {}    -- pageObj: 视图状态表；pageBuilt: 页面容器
local cur = 0
local tr = { active = false }
local indicator, tabLabels = nil, {}
local lbName, lbDesc, lbClock, lbDate, lbFps, lbInfo
local fpsTxt, infoTxt

-- 时间基准
local TICKS_PER_MS = 1
local FRAME_MS = T.perf.frame_ms
local AUTO_SEC = 20          -- 无操作自动轮播间隔
local idleT = 0

local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    if sys and sys.mtime then return sys.mtime() end
    return os.time() * 1000
end

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end   -- ticks 是 uint32，跨回绕会得到负数
    return d
end

local function init_timebase()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
        log.info("aurora", string.format("时间基准 mcu.hz()=%d，每 tick %.1f ms",
            hz, 1000 / hz))
    else
        TICKS_PER_MS = 1
        log.info("aurora", "时间基准 mcu.hz() 不可用，按 1 tick/ms")
    end
end

-- ==================== 极光背景 ====================
local RIBBON = {
    { y = 0.24, amp = 34, freq = 1.55, sp = 0.55, ph = 0.0, hue = 188, w = 9 },
    { y = 0.52, amp = 46, freq = 1.10, sp = 0.42, ph = 2.1, hue = 286, w = 11 },
    { y = 0.78, amp = 30, freq = 1.95, sp = 0.68, ph = 4.3, hue = 168, w = 8 },
}
local BG_PTS = 15

local function build_bg_shape()
    local o = { pool = fx.pool(), star = {} }
    local rnd = fx.rng(861022)
    for i = 1, 42 do
        o.star[i] = {
            x = math.floor(rnd() * T.stage.w),
            y = math.floor(rnd() * T.stage.h),
            ph = rnd() * fx.TAU,
            r = (rnd() < 0.2) and 2 or 1,
        }
    end
    o.xs, o.ys = {}, {}
    return o
end

local function draw_bg(o, t)
    local P = o.pool
    local W, H = T.stage.w, T.stage.h
    P:reset()

    -- ---- 三条极光丝带：宽暗光晕 + 细亮灯芯，两层叠出"发光" ----
    for r = 1, #RIBBON do
        local d = RIBBON[r]
        for i = 1, BG_PTS do
            local f = (i - 1) / (BG_PTS - 1)
            local x = f * W
            -- 两个不同频率的正弦叠加：单频丝带会像心电图一样规律，太假
            local y = d.y * H
                + math.sin(f * d.freq * fx.TAU + t * d.sp + d.ph) * d.amp
                + math.sin(f * d.freq * 2.7 * fx.TAU - t * d.sp * 1.7) * d.amp * 0.35
            o.xs[i], o.ys[i] = x, y
        end
        local col = fx.hsl(d.hue + 10 * math.sin(t * 0.4 + r), 0.9, 0.52)
        for i = 2, BG_PTS do
            P:line(o.xs[i - 1], o.ys[i - 1], o.xs[i], o.ys[i], col, d.w, 20, true)
        end
        for i = 2, BG_PTS do
            P:line(o.xs[i - 1], o.ys[i - 1], o.xs[i], o.ys[i],
                fx.shade(col, 0.25), 2, 78, true)
        end
    end

    -- ---- 星点：亮度按各自相位缓慢呼吸 ----
    for i = 1, #o.star do
        local s = o.star[i]
        local tw = 0.5 + 0.5 * math.sin(t * 0.9 + s.ph)
        P:dot(s.x, s.y, s.r, 0xA8C8E8, math.floor(18 + 90 * tw))
    end

    o.n = P:finish()
    bgShape:set_items(P.items)
end

-- ==================== 静态网格（只画一次） ====================
local function build_grid()
    local P = fx.pool()
    local W, H = T.stage.w, T.stage.h
    P:reset()
    for x = 0, W, 62 do
        P:line(x, 0, x, H, 0x152238, 1, 70)
    end
    for y = 0, H, 60 do
        P:line(0, y, W, y, 0x152238, 1, 70)
    end
    P:finish()
    gridShape:set_items(P.items)
end

-- ==================== 玻璃卡片 ====================
--[[在页面右侧 PANEL 里建一张毛玻璃卡片
不靠图片、不靠阴影（airui.container 的 shadow 参数在当前版本不生效），
质感全靠三层叠出来：
  1) 半透明底（能看见背后的极光）
  2) 顶部 1px 高光条（模拟玻璃边缘反光）
  3) 1px 描边（把卡片从背景里"切"出来）
@return table { root, shape, title, value, sub, accent, w, h }
]]
local function make_card(page, idx, title, accent, value_text, sub_text)
    local ch, cg = T.card.h, T.card.gap
    local y = T.panel.y + (idx - 1) * (ch + cg)
    local x, cw = T.panel.x, T.card.w

    --[[卡片本体用 shape，不用 container
    container 就是 lv_obj_create，默认带 LV_OBJ_FLAG_SCROLLABLE：所有子对象的
    包围盒一旦超出内容区（哪怕 1px），LVGL 就按 AUTO 模式在右/下画滚动条，
    真机上看就是"卡片里多一圈方角细框、底部多一条横线"。
    shape 在 C 层硬编码了 remove(SCROLLABLE)，任何情况都不会出现滑块，
    所以卡片底板也交给它画：圆角填充 + 描边 + 顶部高光 + 左侧分类色条，共 4 个图元，
    只在构建时画一次。]]
    local c = airui.shape({
        parent = page, x = x, y = y, w = cw, h = ch, items = {},
    })
    local bg = fx.pool()
    bg:reset()
    bg:box(0, 0, cw - 1, ch - 1, C.panel, T.o.card, 18)
    bg:frame(0, 0, cw - 1, ch - 1, C.line, 1, 255, 18)
    bg:line(16, 2, cw - 17, 2, accent, 1, 120, true)
    bg:box(1, 22, 2, ch - 45, accent, 150, 1)
    bg:finish()
    c:set_items(bg.items)

    -- 动态图元层：子 shape，视图每 5Hz 覆写它，不会冲掉底板
    local shape = airui.shape({
        parent = c, x = 1, y = 1, w = cw - 2, h = ch - 2, items = {},
    })
    local tb = airui.label({
        parent = c, x = 18, y = 12, w = cw - 36, h = 20,
        text = title, font_size = T.f.title - 3, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local vb = airui.label({
        parent = c, x = 18, y = 32, w = cw - 36, h = 38,
        text = value_text, font_size = T.f.value, color = accent,
        align = airui.TEXT_ALIGN_LEFT,
    })
    local sb = airui.label({
        parent = c, x = 18, y = 74, w = cw - 36, h = 18,
        text = sub_text or "", font_size = T.f.mini, color = C.dim2,
        align = airui.TEXT_ALIGN_LEFT,
    })
    return { root = c, shape = shape, title = tb, value = vb, sub = sb,
        accent = accent, w = cw, h = ch }
end

-- ==================== HUD ====================
local function build_hud()
    hud = airui.container({
        parent = root, x = 0, y = 0, w = SW, h = T.hud.h,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    -- 品牌标记：内嵌菱形 + 十字，纯图元，天然矢量清晰
    local mark = airui.shape({ parent = hud, x = 24, y = 18, w = 40, h = 40, items = {} })
    local P = fx.pool()
    P:reset()
    P:neon(20, 3, 37, 20, C.cyan, 2, 230)
    P:neon(37, 20, 20, 37, C.cyan, 2, 230)
    P:neon(20, 37, 3, 20, C.violet, 2, 200)
    P:neon(3, 20, 20, 3, C.violet, 2, 200)
    P:dot(20, 20, 3, 0xDFF7FF, 240)
    P:finish()
    mark:set_items(P.items)

    airui.label({
        parent = hud, x = 72, y = 10, w = 260, h = 32,
        text = "AURORA", font_size = T.f.h1, color = C.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })
    airui.label({
        parent = hud, x = 74, y = 42, w = 280, h = 20,
        text = "幻境 UI 引擎  Air8607", font_size = T.f.mini, color = C.dim2,
        align = airui.TEXT_ALIGN_LEFT,
    })

    -- 分隔竖线
    airui.container({
        parent = hud, x = 348, y = 20, w = 1, h = 36,
        color = C.line, color_opacity = 255, border_width = 0,
    })

    lbName = airui.label({
        parent = hud, x = 366, y = 12, w = 300, h = 26,
        text = "", font_size = T.f.title + 1, color = C.cyan,
        align = airui.TEXT_ALIGN_LEFT,
    })
    lbDesc = airui.label({
        parent = hud, x = 366, y = 42, w = 320, h = 20,
        text = "", font_size = T.f.mini, color = C.dim,
        align = airui.TEXT_ALIGN_LEFT,
    })

    lbClock = airui.label({
        parent = hud, x = 676, y = 8, w = 200, h = 34,
        text = "--:--:--", font_size = 24, color = C.txt,
        align = airui.TEXT_ALIGN_RIGHT,
    })
    lbDate = airui.label({
        parent = hud, x = 676, y = 44, w = 200, h = 18,
        text = "", font_size = T.f.mini, color = C.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- FPS 胶囊：一个绿色状态点 + 文字，比裸文字更像"仪表"
    local chip = airui.container({
        parent = hud, x = 890, y = 22, w = 110, h = 30,
        color = C.panel, color_opacity = 255, radius = 15,
        border_color = C.line, border_width = 1,
    })
    airui.container({
        parent = chip, x = 12, y = 12, w = 6, h = 6,
        color = C.green, color_opacity = 255, radius = 3, border_width = 0,
    })
    lbFps = airui.label({
        parent = chip, x = 24, y = 5, w = 80, h = 20,
        text = "FPS --", font_size = T.f.mini, color = C.txt,
        align = airui.TEXT_ALIGN_LEFT,
    })
    lbInfo = airui.label({
        parent = hud, x = 890, y = 56, w = 110, h = 16,
        text = "", font_size = 11, color = C.dim2,
        align = airui.TEXT_ALIGN_RIGHT,
    })

    -- 顶栏底部分隔线
    airui.container({
        parent = hud, x = 0, y = T.hud.h - 1, w = SW, h = 1,
        color = C.line, color_opacity = 255, border_width = 0,
    })
end

-- ==================== DOCK ====================
local function tab_x(i)
    return T.tabs.x + (i - 1) * (T.tabs.w + T.tabs.gap)
end

local function build_dock()
    dock = airui.container({
        parent = root, x = T.dock.x, y = T.dock.y, w = T.dock.w, h = T.dock.h,
        color = C.panel, color_opacity = 245, radius = 20,
        border_color = C.line, border_width = 1,
    })

    -- 指示器先建，页签后建 → 页签压在指示器上面，文字才不会被盖住
    indicator = airui.container({
        parent = dock, x = tab_x(1), y = T.tabs.y, w = T.tabs.w, h = T.tabs.h,
        color = C.cyan, color_opacity = 26, radius = 16,
        border_color = C.cyan, border_width = 1,
    })

    for i, v in ipairs(VIEWS) do
        local tab = airui.container({
            parent = dock, x = tab_x(i), y = T.tabs.y, w = T.tabs.w, h = T.tabs.h,
            radius = 16, border_width = 0,
            on_click = function() M.select(i) end,
        })
        -- 文字左右各留 8px：内容区不能被子对象填满，否则会触发滚动条
        local lbl = airui.label({
            parent = tab, x = 8, y = 14, w = T.tabs.w - 16, h = 22,
            text = v.name .. "  " .. v.en, font_size = T.f.body, color = C.dim,
            align = airui.TEXT_ALIGN_CENTER,
        })
        -- 文字也必须绑点击：触点落在文字上时，LVGL 命中测试会先撞到 label
        lbl:set_on_click(function() M.select(i) end)
        tabLabels[i] = lbl
    end
end

-- ==================== 页面与切换 ====================
local function build_page(i)
    local page = airui.container({
        parent = stage, x = 0, y = 0, w = T.stage.w, h = T.stage.h,
        radius = 0, border_width = 0,
    })
    local view = VIEWS[i]
    pageObj[i] = view.build(page, T.hero.w, T.hero.h, function(idx, title, accent, v, s)
        return make_card(page, idx, title, accent, v, s)
    end)
    -- 主视觉容器：把 hero 单独包一层，方便视图只在自己区域内画
    pageBuilt[i] = page
    return page
end

--[[切换页面
@param number i 目标页（1..#VIEWS）
@bool instant 跳过过渡动画（启动首屏用）
]]
function M.select(i, instant)
    if i < 1 or i > #VIEWS then return end
    if cur == i and not tr.active then return end
    idleT = 0

    local target = pageBuilt[i] or build_page(i)
    if instant or cur == 0 then
        for k = 1, #VIEWS do
            if pageBuilt[k] then pageBuilt[k]:set_hidden(k ~= i) end
        end
        target:set_pos(0, 0)
        target:set_hidden(false)
        cur = i
        M.hud_refresh(true)
        M.dock_refresh()
        return
    end

    local dir = (i > cur) and 1 or -1
    local old = pageBuilt[cur]
    target:set_pos(dir * T.stage.w, 0)
    target:set_hidden(false)
    tr.active = true
    tr.dir = dir
    tr.t = 0
    tr.from = old
    tr.to = target
    tr.toIdx = i
    cur = i
    M.hud_refresh(true)
    M.dock_refresh()
    log.info("aurora", "切换页面", VIEWS[i].id, VIEWS[i].name)
end

local function step_transition(dt)
    if not tr.active then return end
    tr.t = tr.t + dt / 0.34
    local e = fx.ease_out(tr.t)
    local W = T.stage.w
    --[[set_pos 在 C 层是 luaL_checkinteger：传 123.45 会直接抛
    "number has no integer representation" 并终止整个 Lua VM。
    缓动出来的位置天然是小数，所以每一次 set_pos 都必须先取整。]]
    local off = math.floor(tr.dir * W * (1 - e))
    if tr.from then tr.from:set_pos(-off, 0) end
    tr.to:set_pos(off, 0)

    -- 过渡光带：一条 3px 的亮线跟着前沿扫过，把"切换"这个动作本身画出来
    sweep:set_pos(T.stage.x + off - 1, T.stage.y)
    local a = math.sin(math.pi * fx.clamp(tr.t, 0, 1))
    sweep:set_hidden(a < 0.02)
    sweep:set_color(tr.dir > 0 and C.cyan or C.violet, math.floor(190 * a))

    if tr.t >= 1 then
        tr.active = false
        if tr.from then
            tr.from:set_pos(0, 0)
            tr.from:set_hidden(true)
        end
        tr.to:set_pos(0, 0)
        sweep:set_hidden(true)
        tr.from, tr.to = nil, nil
    end
end

-- ==================== HUD / DOCK 文字刷新 ====================
function M.hud_refresh(force)
    local v = VIEWS[cur]
    if not v then return end
    local name = v.name .. "  " .. v.en
    if force or name ~= M._name then
        M._name = name
        lbName:set_text(name)
        lbDesc:set_text(v.desc)
    end
end

function M.dock_refresh()
    for i, lbl in ipairs(tabLabels) do
        lbl:set_color((i == cur) and C.cyan or C.dim)
    end
    tr.ind_target = tab_x(cur)
    if tr.ind_x == nil then tr.ind_x = tr.ind_target end
end

-- ==================== 构建整屏 ====================
function M.build()
    root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    --[[舞台视口：透明底，页面在其中左右滑动
    LVGL 默认把子对象裁到父边界内（airui.container 也清掉了 pad），
    所以页面滑出视口的部分会被裁掉；容器本身的 bg_opa 设为 TRANSP，
    这样既裁剪又不挡背后的极光层。]]
    stage = airui.container({
        parent = root, x = T.stage.x, y = T.stage.y, w = T.stage.w, h = T.stage.h,
        radius = 0, border_width = 0,
    })

    gridShape = airui.shape({
        parent = stage, x = 0, y = 0, w = T.stage.w, h = T.stage.h, items = {},
    })
    build_grid()

    bgShape = airui.shape({
        parent = stage, x = 0, y = 0, w = T.stage.w, h = T.stage.h, items = {},
    })
    M.bg = build_bg_shape()

    -- HUD 与 DOCK 在 stage 之后创建 → 永远压在舞台之上
    build_hud()
    build_dock()

    -- 过渡光带挂 root（在 stage 之上），避免被页面覆盖
    sweep = airui.container({
        parent = root, x = T.stage.x, y = T.stage.y, w = 3, h = T.stage.h,
        color = C.cyan, color_opacity = 0, radius = 0, border_width = 0,
    })
    sweep:set_hidden(true)

    -- 首屏：不走过渡，直接落位
    M.select(1, true)

    -- 触摸订阅：把屏幕坐标换成页面局部坐标后转发给当前视图
    airui.touch_subscribe(function(state, x, y)
        M.on_touch(state, x, y)
    end)
    log.info("aurora", "界面构建完成")
end

-- ==================== 触摸路由 ====================
local TP_DOWN, TP_UP = airui.TP_DOWN, airui.TP_UP
local touchOwner = nil

--[[把屏幕坐标转发给当前页面
只有落在 HERO 矩形内的触点才交给视图处理：
PANEL 里的原生 slider / switch 需要自己接收触摸，不能被粒子发射器抢走。
]]
function M.on_touch(state, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    idleT = 0
    if tr.active then return end          -- 过渡动画期间忽略触摸，避免状态错乱

    local hx, hy = x - T.stage.x, y - T.stage.y
    local inside = hx >= T.hero.x and hx < T.hero.x + T.hero.w
        and hy >= T.hero.y and hy < T.hero.y + T.hero.h

    local ev
    if state == TP_DOWN then
        ev = "down"
    elseif state == TP_UP then
        ev = "up"
    else
        ev = "move"
    end

    local v = VIEWS[cur]
    local o = pageObj[cur]
    if not v or not o then return end

    -- 按下时若不在 HERO 内，本轮的 move/up 也不再转发（手指划出区域不算交互）
    if ev == "down" then
        touchOwner = inside and cur or nil
    elseif touchOwner ~= cur then
        return
    end

    if v.touch then
        local ok, err = pcall(v.touch, o, ev, hx - T.hero.x, hy - T.hero.y)
        if not ok then log.error("aurora", "视图触摸回调异常", err) end
    end
    if ev == "up" then touchOwner = nil end
end

-- ==================== 主循环 ====================
function M.run()
    init_timebase()

    local t = 0
    local prev = now_ms()
    local waitMs = FRAME_MS
    local frames, fsum, fps = 0, 0, 0
    local costAvg = 0
    local hudT, panelT = 0, 0
    local frameNo = 0
    local clockT = 0

    while true do
        sys.wait(waitMs)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now
        --[[动画步长用固定值
        Air8607 的 tick 分辨率约 20ms，比 33ms 的帧间隔还粗，
        直接用 tick 差当 dt 只能取到 20/40ms，动画会"顿"。
        sys.wait 本身是 1ms 精度的软定时器，节拍是准的，所以固定步长最平滑；
        只有真的被挂起超过 3 帧，才按真实时间补跳。]]
        local dt
        if realMs > FRAME_MS * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = FRAME_MS / 1000 end
        else
            dt = FRAME_MS / 1000
        end
        t = t + dt
        frameNo = frameNo + 1

        local t0 = now_ms()

        -- ---- 1、极光背景（降频，省掉 2/3 的全舞台重绘）----
        if frameNo % T.perf.bg_every == 0 then
            draw_bg(M.bg, t)
        end

        -- ---- 2、当前页面主视觉（每帧）----
        local v = VIEWS[cur]
        local o = pageObj[cur]
        if v and o and not tr.active then
            local ok, err = pcall(v.update, o, t, dt)
            if not ok then
                log.error("aurora", "页面帧更新失败", v.id, err)
                sys.wait(500)
            end
        elseif tr.active and tr.toIdx then
            -- 过渡中只推进新页面的动画，旧页面保持静止（它马上就被移出屏幕）
            local nv = VIEWS[tr.toIdx]
            local no = pageObj[tr.toIdx]
            if nv and no then pcall(nv.update, no, t, dt) end
        end

        -- ---- 3、卡片与数值（5Hz，避免每帧重排文本）----
        panelT = panelT + dt
        if panelT >= 0.2 then
            local pdt = panelT
            panelT = 0
            if v and o then
                local ok, err = pcall(v.panel, o, t, pdt)
                if not ok then log.error("aurora", "卡片刷新失败", err) end
            end
        end

        -- ---- 4、页面过渡 ----
        --[[过渡是唯一"改容器坐标"的地方，单独 pcall：
        一旦这里抛错，整个 Lua VM 会退出并重启，演示界面直接黑屏重来。
        出错就把过渡立即复位，宁可少一段动画也不要把机器跑崩。]]
        local tok, terr = pcall(step_transition, dt)
        if not tok then
            log.error("aurora", "页面过渡异常，已复位", terr)
            tr.active = false
            tr.from, tr.to = nil, nil
            sweep:set_hidden(true)
        end

        -- ---- 5、Dock 指示器：弹簧跟随当前页 ----
        if tr.ind_target and tr.ind_x then
            local nx = fx.approach(tr.ind_x, tr.ind_target, 0.22, dt)
            if math.abs(nx - tr.ind_target) < 0.4 then nx = tr.ind_target end
            if nx ~= tr.ind_x then
                tr.ind_x = nx
                indicator:set_pos(math.floor(nx), T.tabs.y)
            end
        end

        local cost = tick_diff(now_ms(), t0) / TICKS_PER_MS
        costAvg = costAvg + (cost - costAvg) * 0.15

        -- ---- 6、FPS 统计（用真实时间累计，长期平均才准）----
        frames = frames + 1
        fsum = fsum + realMs / 1000
        if fsum >= 0.5 then
            fps = frames / fsum
            frames, fsum = 0, 0
        end

        -- ---- 7、HUD 文字（4Hz）----
        hudT = hudT + realMs / 1000
        if hudT >= T.perf.hud_ms / 1000 then
            hudT = 0
            local lvFps = 0
            local dbg = airui.debug()
            if type(dbg) == "table" then lvFps = dbg.fps or 0 end
            local s = string.format("FPS %d", math.floor(fps + 0.5))
            if s ~= fpsTxt then
                fpsTxt = s
                lbFps:set_text(s)
            end
            s = string.format("%s %d", lvFps > 0 and ("LV" .. lvFps) or "LV--",
                (o and o.n) or 0)
            if s ~= infoTxt then
                infoTxt = s
                lbInfo:set_text(s)
            end
        end

        -- ---- 8、时钟（1Hz）----
        clockT = clockT + realMs / 1000
        if clockT >= 1 then
            clockT = 0
            local d = os.date("*t")
            if d then
                local s = string.format("%02d:%02d:%02d", d.hour, d.min, d.sec)
                if s ~= M._clk then
                    M._clk = s
                    lbClock:set_text(s)
                end
                local w = string.format("%04d-%02d-%02d", d.year, d.month, d.day)
                if w ~= M._date then
                    M._date = w
                    lbDate:set_text(w)
                end
            end
        end

        -- ---- 9、无人操作自动轮播 ----
        idleT = idleT + realMs / 1000
        if idleT >= AUTO_SEC and not tr.active then
            local nx = cur % #VIEWS + 1
            local ok2, err2 = pcall(M.select, nx)
            if not ok2 then log.error("aurora", "自动轮播切页失败", err2) end
        end

        -- ---- 10、补偿式节拍 ----
        -- sys.wait 是"至少等这么久"，实际周期 = 帧间隔 + 本帧耗时，
        -- 不补偿的话工作越重帧率越低，会自我恶化
        local w = FRAME_MS - cost
        if w < 2 then w = 2 end
        waitMs = w
    end
end

return M
