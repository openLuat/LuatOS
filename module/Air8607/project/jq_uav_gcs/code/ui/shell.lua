--[[
@module  shell
@summary UAV GCS - 外壳（顶栏 / 标签栏 / 页面切换 / 主循环 / 触摸分发）
@version 1.0
@date    2026.11.02

=== 分层的顺序 ===
root(container)
 ├─ 顶栏        y   0..52   站名 / 模式 / 链路 / 卫星 / 电压 / 电量 / 时钟
 ├─ 页面容器 x5  y  52..548  每个页面一个 container，切页只做 set_hidden
 └─ 标签栏      y 548..600  五个标签

页面一次全建好、切页只切显隐：
重建页面的代价是几百个 LVGL 对象 + 一次全屏重绘，切一次卡一次；
全建好的代价只有内存，而这台机器有 PSRAM，稳赚。

=== 主循环 ===
30ms 一拍（避开 LVGL 33ms 的刷新拍频）：
  仿真 30Hz 永远跑（这样日志时间、航迹、机身姿态都连续）
  姿态页 30fps 重绘（球在转，掉帧最明显）
  其余页面 10Hz 重绘（数字类信息，10Hz 已经比人眼快）
  顶栏 2Hz
=== 空闲演示 ===
8 秒没人碰屏幕就自动进入演示航线（解锁 -> 起飞 -> 巡航 -> 返航 -> 降落），
一碰屏幕立刻交还手动控制。展台上没人操作时画面也不会是死的。
]]
local fx = require "fx"
local T = require "theme"
local parts = require "parts"
local sim = require "sim"

local C = T.c
local TP_DOWN, TP_HOLD, TP_UP = T.TP_DOWN, T.TP_HOLD, T.TP_UP

local M = {}

local o = {
    cur = 1,
    pages = {},
    tab = {},
    pill = {},
    top = {},
    acc = 0,
    top_acc = 0,
}

local tabs = T.pages
local P = nil

-- ==================== 时间 ====================
local function now_ms()
    if mcu and mcu.ticks then return mcu.ticks() end
    return os.time() * 1000
end

local TICKS_PER_MS = 1

local function tick_diff(a, b)
    local d = a - b
    if d < 0 then d = d + 4294967296 end
    return d
end

-- ==================== 顶栏 ====================
local PILL_W, PILL_H, PILL_Y, PILL_X0, PILL_GAP = 118, 34, 9, 300, 6

local function build_top()
    -- 背景 + 下边框
    local bg = airui.shape({
        parent = o.root, x = 0, y = 0, w = T.screen.w, h = T.top.h, items = {},
    })
    P:reset()
    P:box(0, 0, T.screen.w - 1, T.top.h - 1, C.panel, 255, 0)
    P:line(0, T.top.h - 1, T.screen.w - 1, T.top.h - 1, C.line, 1, 255, false)
    P:box(0, 0, 4, T.top.h - 1, C.cyan, 220, 0)
    P:finish()
    bg:set_items(P.items)

    parts.lbl(o.root, 18, 8, 200, 26, "UAV GCS", T.f.mid, C.txt, airui.TEXT_ALIGN_LEFT)
    parts.lbl(o.root, 118, 14, 180, 20, "X4-8607 地面站", T.f.mini, C.dim,
        airui.TEXT_ALIGN_LEFT)
    o.top.demo = parts.lbl(o.root, 200, 32, 130, 16, "", T.f.mini, C.amber,
        airui.TEXT_ALIGN_LEFT)

    -- 状态胶囊
    for i = 1, 5 do
        local x = PILL_X0 + (i - 1) * (PILL_W + PILL_GAP)
        local s = airui.shape({
            parent = o.root, x = x, y = PILL_Y, w = PILL_W, h = PILL_H, items = {},
        })
        o.pill[i] = {
            shape = s, x = x, y = PILL_Y, w = PILL_W, h = PILL_H,
            label = parts.lbl(o.root, x + 14, PILL_Y + 7, PILL_W - 20, 20, "--",
                T.f.sub, C.dim, airui.TEXT_ALIGN_LEFT),
            col = -1,
        }
    end

    o.top.clock = parts.lbl(o.root, 920, 9, 90, 24, "--:--", T.f.mid, C.txt,
        airui.TEXT_ALIGN_RIGHT)
    o.top.date = parts.lbl(o.root, 900, 33, 110, 16, "", T.f.mini, C.dim2,
        airui.TEXT_ALIGN_RIGHT)
end

local function paint_pill(i, col)
    local p = o.pill[i]
    if p.col == col then return end
    p.col = col
    P:reset()
    P:box(0, 0, PILL_W - 1, PILL_H - 1, 0x0A1220, 240, 8)
    P:frame(0, 0, PILL_W - 1, PILL_H - 1, C.line, 1, 210, 8)
    P:box(0, 7, 3, PILL_H - 15, col, 240, 2)
    P:finish()
    p.shape:set_items(P.items)
end

local function update_top()
    local s = sim.s
    if not s then return end
    paint_pill(1, s.mode == 4 and C.amber or C.cyan)
    parts.text(o.pill[1].label, "模式 " .. sim.MODES[s.mode])

    local link_col = s.link and C.green or C.red
    paint_pill(2, link_col)
    parts.text(o.pill[2].label, "链路 " .. (s.link and "在线" or "断开"))

    paint_pill(3, (s.sats >= 8) and C.green or C.amber)
    parts.text(o.pill[3].label, "卫星 " .. tostring(s.sats))

    paint_pill(4, (s.volt > 14.2) and C.blue or C.amber)
    parts.text(o.pill[4].label, string.format("电压 %.1fV", s.volt))

    paint_pill(5, (s.batt > 25) and C.green or C.red)
    parts.text(o.pill[5].label, string.format("电量 %d%%", math.floor(s.batt + 0.5)))

    local ok, clk = pcall(os.date, "%H:%M:%S")
    parts.text(o.top.clock, (ok and clk) or "--:--")
    local ok2, day = pcall(os.date, "%m-%d")
    parts.text(o.top.date, (ok2 and day) or "")

    parts.text(o.top.demo, s.demo and "自动演示中" or (s.manual and "手动接管" or ""))
end

-- ==================== 标签栏 ====================
local TAB_W, TAB_H, TAB_GAP, TAB_Y = T.tabs.w, T.tabs.h, T.tabs.gap, T.tabs.y

local function tab_x(i)
    local total = #tabs * TAB_W + (#tabs - 1) * TAB_GAP
    return math.floor((T.screen.w - total) / 2) + (i - 1) * (TAB_W + TAB_GAP)
end

local function build_tabs()
    local bg = airui.shape({
        parent = o.root, x = 0, y = T.tabs.y, w = T.screen.w, h = T.tabs.h, items = {},
    })
    P:reset()
    P:box(0, 0, T.screen.w - 1, T.tabs.h - 1, C.panel, 255, 0)
    P:line(0, 0, T.screen.w - 1, 0, C.line, 1, 255, false)
    P:finish()
    bg:set_items(P.items)

    for i = 1, #tabs do
        local x = tab_x(i)
        local s = airui.shape({
            parent = o.root, x = x, y = TAB_Y + 4, w = TAB_W, h = TAB_H - 8, items = {},
        })
        o.tab[i] = {
            shape = s, x = x, y = TAB_Y + 4, w = TAB_W, h = TAB_H - 8,
            name = parts.lbl(o.root, x + 20, TAB_Y + 12, 80, 24, tabs[i].name,
                T.f.body, C.dim, airui.TEXT_ALIGN_LEFT),
            en = parts.lbl(o.root, x + TAB_W - 62, TAB_Y + 16, 48, 16, tabs[i].en,
                T.f.mini, C.dim2, airui.TEXT_ALIGN_RIGHT),
            on = nil,
        }
    end
end

local function paint_tab(i, on)
    local t = o.tab[i]
    if t.on == on then return end
    t.on = on
    P:reset()
    if on then
        P:box(0, 0, TAB_W - 1, TAB_H - 9, C.cyan, 28, 8)
        P:frame(0, 0, TAB_W - 1, TAB_H - 9, C.cyan, 1, 170, 8)
        P:box(14, TAB_H - 12, TAB_W - 28, 3, C.cyan, 245, 1)
    else
        P:box(0, 0, TAB_W - 1, TAB_H - 9, C.panel2, 90, 8)
    end
    P:finish()
    t.shape:set_items(P.items)
    t.name:set_color(on and C.txt or C.dim)
    t.en:set_color(on and C.cyan or C.dim2)
end

-- ==================== 页面 ====================
local MODS = {
    require "page_att",
    require "page_data",
    require "page_param",
    require "page_func",
    require "page_map",
}

local function build_pages()
    for i = 1, #MODS do
        local c = airui.container({
            parent = o.root,
            x = 0, y = T.content.y, w = T.screen.w, h = T.content.h,
            color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
        })
        o.pages[i] = { box = c, mod = MODS[i] }
        MODS[i].build(c)
        c:set_hidden(i ~= 1)
    end
end

function M.switch(i)
    if i == o.cur then return end
    local old = o.pages[o.cur]
    if old and old.mod.leave then old.mod.leave() end
    if old then old.box:set_hidden(true) end

    o.pages[i].box:set_hidden(false)
    o.cur = i
    o.acc = 99   -- 强制立刻重绘一帧，避免切过去先空白

    for k = 1, #tabs do paint_tab(k, k == i) end
    log.info("uav", "切换到页面 " .. tabs[i].name)
end

-- ==================== 构建 ====================
function M.build()
    P = fx.pool()

    o.root = airui.container({
        parent = nil, x = 0, y = 0, w = T.screen.w, h = T.screen.h,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    build_top()
    build_pages()
    build_tabs()

    for k = 1, #tabs do paint_tab(k, k == 1) end
    update_top()

    airui.touch_subscribe(function(state, x, y)
        M.on_touch(state, x, y)
    end)
    log.info("uav", "地面站界面构建完成")
end

-- ==================== 触摸 ====================
function M.on_touch(state, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return end
    if not sim.s then return end

    -- 任何触摸都算"有人在用"，演示靠这个让位
    if state == TP_DOWN then
        sim.touch()
    end

    if state == TP_DOWN then
        -- 标签栏
        if y >= T.tabs.y then
            for i = 1, #tabs do
                local t = o.tab[i]
                if parts.hit(x, y, t.x, t.y, t.w, t.h) then
                    M.switch(i)
                    return
                end
            end
            return
        end
        -- 顶栏：点链路胶囊 = 连接 / 断开
        if y < T.top.h then
            if parts.hit(x, y, PILL_X0, PILL_Y, PILL_W, PILL_H) then
                return
            end
            for i = 2, 5 do
                local p = o.pill[i]
                if parts.hit(x, y, p.x, p.y, p.w, p.h) then
                    if i == 2 then
                        sim.connect(not sim.s.link)
                    end
                    return
                end
            end
            return
        end
    end

    -- 页面（坐标换成内容区坐标：页面容器在 y=52）
    local pg = o.pages[o.cur]
    if pg and pg.mod.on_touch then
        pg.mod.on_touch(state, x, y - T.content.y)
    end
end

-- ==================== 主循环 ====================
function M.run()
    local hz = mcu and mcu.hz and mcu.hz()
    if type(hz) == "number" and hz > 1 then
        TICKS_PER_MS = hz / 1000
    end

    local prev = now_ms()
    local t = 0

    while true do
        sys.wait(T.perf.frame_ms)

        local now = now_ms()
        local realMs = tick_diff(now, prev) / TICKS_PER_MS
        prev = now
        local dt = T.perf.frame_ms / 1000
        if realMs > T.perf.frame_ms * 3 or realMs <= 0 then
            dt = realMs / 1000
            if dt <= 0 or dt > 0.25 then dt = T.perf.frame_ms / 1000 end
        end

        local ok, err = pcall(sim.update, dt)
        if not ok then log.error("uav", "仿真异常", err) end
        t = sim.s.t

        -- 顶栏 2Hz
        o.top_acc = o.top_acc + dt
        if o.top_acc >= 0.5 then
            o.top_acc = 0
            local ok2, err2 = pcall(update_top)
            if not ok2 then log.error("uav", "顶栏异常", err2) end
        end

        -- 空闲 -> 自动演示
        if sim.s.link and not sim.s.demo and sim.s.idle > T.perf.idle_sec then
            sim.s.demo = true
            sim.s.mission = "idle"
            sim.s.mt = 0
            sim.log("info", "长时间无操作，进入自动演示")
        end

        -- 页面绘制：姿态页 30fps，其余 10Hz
        o.acc = o.acc + dt
        local every = (o.cur == 1) and 0 or (T.perf.slow_ms / 1000)
        if o.acc >= every then
            o.acc = 0
            local pg = o.pages[o.cur]
            if pg and pg.mod.draw then
                local ok3, err3 = pcall(pg.mod.draw, dt, t)
                if not ok3 then log.error("uav", "页面异常", err3) end
            end
        end
    end
end

return M
