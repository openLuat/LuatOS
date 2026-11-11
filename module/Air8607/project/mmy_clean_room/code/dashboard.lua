--[[
@module  dashboard
@summary 华康无菌车间 - 页面外壳（顶栏 / 页签 / 内容区 / 提示行 / 触摸分发）
@version 2.0
@date    2026.11.11

=== 为什么拆页 ===
一块 1024x600 的屏塞五块面板，每块都只能分到 300 像素宽：
压差平面缩到看不清门洞，趋势只剩 230 像素宽，事件一屏 5 条。
车间里真正会被盯着看的是"哪一间失守"，其余都是追问细节时才需要。
所以拆成四页，一页回答一类问题，页签常驻，切页零重建：

  1 总览   OVERVIEW   哪一间正在失守？压差梯度 + 粒子 + 待确认事件 + 今日概览
  2 气候   CLIMATE    是在掉，还是一直在往下走？24h 温湿度大图 + 三张读数卡
  3 送风   AIR        送风侧还撑不撑得住？AHU 参数 + 三级滤器 + 风路 + 能耗
  4 事件   EVENTS     刚才发生了什么，谁还没确认？完整事件表 + 筛选 + 确认

=== 页面接口（page_*.lua 只要实现这四个）===
  M.title / M.en / M.hint   页签名、英文名、提示行文案
  M.build(root)             在给定容器里建控件并画首帧
  M.enter()                 切入本页时重绘一次（数据已经变了）
  M.update(dt, idle, now)   只在本页可见时被调用
  M.on_touch(x, y)          坐标已减去内容区原点；返回 true 表示已处理

=== 切页为什么不重建控件 ===
LVGL 控件挂在 airui 的 timer 上，触摸回调跑在输入线程；在回调里销毁再建一整页
控件是这块屏最容易崩的写法。四页开机各建一次，切页只 set_hidden，
代价是常驻内存多几十 KB，换来切页 0 帧卡顿。

=== 全局节拍 ===
时钟 250ms、状态 250ms、模式胶囊 500ms；页面各自决定自己重绘什么。
]]

local T = require "theme"
local fx = require "fx"
local kit = require "kit"
local data = require "room_data"
local voice = require "voice"

-- 四页在这里 require：页面只依赖 theme/kit/fx/data，不回指 dashboard，没有循环引用
local pages = {
    require "page_overview",
    require "page_climate",
    require "page_air",
    require "page_alarms",
}

local M = {}

local c, f = T.c, T.f
local P = fx.pool()

local o = {
    page = 1,
    now = 0,
    idle = 0,
    tClock = 0, tChip = 0, tStatus = 0,
}
M.o = o

local fmt, floor = string.format, math.floor
local function f1(v) return fmt("%.1f", v) end
local function f0(v) return fmt("%d", floor(v + 0.5)) end

local function hit(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

local function new_shape(parent, w, h)
    return airui.shape({ parent = parent, x = 0, y = 0, w = w, h = h })
end

local function tab_x(i)
    return T.nav.x + (i - 1) * (T.nav.w + T.nav.gap)
end

-- ==================== 背景 ====================
local function build_bg()
    o.root = airui.container({
        x = 0, y = 0, w = T.screen.w, h = T.screen.h,
        color = c.bg, color_opacity = 255, border_width = 0,
    })
    -- 顶部一条冷光带，压住整块屏的重心
    local sh = new_shape(o.root, T.screen.w, 60)
    P:reset()
    for i = 0, 59 do
        local a = floor(26 * (1 - i / 60))
        if a > 0 then P:box(0, i, T.screen.w, 1, c.ice, a, 0) end
    end
    sh:set_items(P:finish())

    -- 内容区与提示行之间一条极淡的分隔，避免底部信息"浮"在页面里
    airui.container({
        parent = o.root, x = 12, y = T.body.y + T.body.h + 2, w = 1000, h = 1,
        color = c.line, color_opacity = 140, border_width = 0,
    })
end

-- ==================== 顶栏 ====================
local function build_top()
    local bar = airui.container({
        parent = o.root, x = 0, y = 0, w = T.screen.w, h = T.top.h,
        color = c.panel, color_opacity = 255, border_width = 0,
    })
    airui.container({
        parent = bar, x = 0, y = T.top.h - 1, w = T.screen.w, h = 1,
        color = c.line, color_opacity = 255, border_width = 0,
    })

    kit.text(bar, 20, 5, 360, 26, 20, c.txt, airui.TEXT_ALIGN_LEFT, "华康生物 无菌制剂车间")
    kit.text(bar, 20, 31, 360, 16, 11, c.dim2, airui.TEXT_ALIGN_LEFT, "HUAKANG BIO  ASEPTIC WORKSHOP")

    local function stat(x, title, col, val)
        kit.text(bar, x, 9, 96, 14, 11, c.dim2, airui.TEXT_ALIGN_LEFT, title)
        return kit.text(bar, x, 25, 96, 22, 16, col, airui.TEXT_ALIGN_LEFT, val)
    end
    o.sysState = stat(380, "系统状态", c.mint, "运行中")
    o.gradeState = stat(482, "A 级房间", c.ice, "2 / 2")
    o.overState = stat(584, "超标房间", c.txt, "0")

    o.clock = kit.text(bar, 700, 8, 92, 30, 22, c.txt, airui.TEXT_ALIGN_RIGHT, "00:00")
    kit.text(bar, 700, 34, 92, 14, 11, c.dim2, airui.TEXT_ALIGN_RIGHT, "本班")

    -- 模式胶囊：整块可点，循环切换；shape 覆盖整个顶栏，绘制用 bar 内坐标
    o.chipShape = new_shape(bar, T.screen.w, T.top.h)
    o.chipName = kit.text(bar, 856, 6, 150, 24, 17, c.ink, airui.TEXT_ALIGN_LEFT, "生产")
    o.chipEn = kit.text(bar, 856, 28, 150, 14, 10, c.bg, airui.TEXT_ALIGN_LEFT, "PRODUCTION")
end

local function draw_chip()
    local mo = data.modes[data.mode]
    P:reset()
    P:box(812, 5, 204, 46, c.ice, 235, 6)
    P:box(818, 10, 36, 36, c.bg, 70, 5)
    for i = 0, 2 do
        P:line(828 + i * 7, 17, 828 + i * 7, 39, c.bg, 2, 190, true)
    end
    o.chipShape:set_items(P:finish())
    kit.put(o.chipName, mo.name, o, "chip")
    kit.put(o.chipEn, mo.en, o, "chipen")
end

-- ==================== 页签 ====================
local function build_nav()
    local bar = airui.container({
        parent = o.root, x = 0, y = T.nav.y, w = T.screen.w, h = T.nav.h,
        color = c.bg, color_opacity = 255, border_width = 0,
    })
    o.navShape = new_shape(bar, T.screen.w, T.nav.h)

    o.navLab = {}
    for i = 1, #pages do
        local x = tab_x(i)
        local E = {}
        E.idx = kit.text(bar, x + 12, 13, 22, 18, 11, c.dim2, airui.TEXT_ALIGN_LEFT,
                         fmt("%d", i))
        E.name = kit.text(bar, x + 34, 7, 130, 24, 17, c.dim, airui.TEXT_ALIGN_LEFT, pages[i].title)
        E.en = kit.text(bar, x + 34, 28, 130, 14, 10, c.dim2, airui.TEXT_ALIGN_LEFT, pages[i].en)
        o.navLab[i] = E
    end

    -- 右侧：日期 + 页码。日期放这里是因为顶栏 700 以后已经被时钟和胶囊占满
    o.navDate = kit.text(bar, 700, 12, 150, 20, 12, c.dim2, airui.TEXT_ALIGN_RIGHT, "")
    o.navPage = kit.text(bar, 862, 10, 150, 22, 14, c.dim, airui.TEXT_ALIGN_RIGHT, "1 / 4")
end

local function draw_nav()
    P:reset()
    for i = 1, #pages do
        local x = tab_x(i)
        if i == o.page then
            P:box(x, 3, T.nav.w, 38, c.ice, 24, 6)
            P:frame(x, 3, T.nav.w, 38, c.ice, 1, 110, 6)
            P:box(x + 12, 39, T.nav.w - 24, 2, c.ice, 220, 1)
        else
            P:frame(x, 3, T.nav.w, 38, c.line, 1, 150, 6)
        end
    end
    o.navShape:set_items(P:finish())

    for i = 1, #pages do
        local E = o.navLab[i]
        local on = (i == o.page)
        kit.tint(E.name, on and c.ice or c.dim, o, "nt" .. i)
        kit.tint(E.idx, on and c.ice or c.dim2, o, "nx" .. i)
        kit.tint(E.en, on and c.cyan or c.dim2, o, "ne" .. i)
    end
    kit.put(o.navPage, fmt("%d / %d", o.page, #pages), o, "np")
end

-- ==================== 内容区 ====================
local function build_pages()
    for i = 1, #pages do
        local p = pages[i]
        p.root = airui.container({
            parent = o.root, x = 0, y = T.body.y, w = T.screen.w, h = T.body.h,
            color = c.bg, color_opacity = 255, border_width = 0,
        })
        p.build(p.root)
        p.root:set_hidden(i ~= o.page)
    end
end

local function switch(i)
    if i == o.page then return end
    o.page = i
    for k = 1, #pages do
        pages[k].root:set_hidden(k ~= i)
    end
    o.idle = 0
    draw_nav()
    if pages[i].enter then pages[i].enter() end
    M.refresh()
end

-- ==================== 提示行 ====================
local function build_hint()
    o.hint = kit.text(o.root, 16, T.hint.y, 610, 24, 12, c.dim2, airui.TEXT_ALIGN_LEFT, "")
    o.isoLb = kit.text(o.root, 640, T.hint.y, 100, 24, 12, c.amber, airui.TEXT_ALIGN_CENTER, "")
    kit.text(o.root, 748, T.hint.y, 10, 24, 12, c.line2, airui.TEXT_ALIGN_CENTER, "|")
    o.voiceLb = kit.text(o.root, 760, T.hint.y, 252, 24, 12, c.dim, airui.TEXT_ALIGN_RIGHT, "")
end

-- ==================== 文字刷新 ====================
function M.refresh()
    local s = data.state
    local p = pages[o.page]

    kit.put(o.clock, os.date("%H:%M:%S"), o, "clk")
    kit.put(o.sysState, "运行中", o, "sys")
    kit.put(o.gradeState, fmt("%d / 2", s.at_grade), o, "grade")
    kit.put(o.overState, s.over > 0 and fmt("%d 间", s.over) or "0", o, "over")
    kit.tint(o.overState, s.over > 0 and c.alarm or c.txt, o, "overc")
    kit.put(o.navDate, os.date("%Y-%m-%d"), o, "nd")

    kit.put(o.hint, p.hint or "", o, "hint")
    if data.sel ~= 0 then
        local r = data.rooms[data.sel]
        kit.put(o.isoLb, r.iso and "解除隔离" or "挂牌隔离", o, "iso")
        kit.tint(o.isoLb, r.iso and c.mint or c.amber, o, "isoc")
    else
        kit.put(o.isoLb, "", o, "iso")
    end

    local vs
    if not voice.ready() then
        vs = "语音不可用（固件无 TTS）"
    elseif voice.enabled() then
        vs = "语音 开  音量 18"
    else
        vs = "语音 关  （点此开启）"
    end
    kit.put(o.voiceLb, vs, o, "voice")
    kit.tint(o.voiceLb, voice.enabled() and c.dim or c.dim2, o, "voicec")
end

-- ==================== 触摸 ====================
function M.on_touch(x, y)
    -- 顶栏模式胶囊
    if hit(x, y, 812, 5, 204, 46) then
        if data.next_mode() then
            o.idle = 0
            draw_chip()
            pages[o.page].enter()
            M.refresh()
            voice.say("已切换至" .. data.modes[data.mode].name .. "模式", 2)
        end
        return true
    end

    -- 页签
    for i = 1, #pages do
        if hit(x, y, tab_x(i), T.nav.y + 3, T.nav.w, 38) then
            switch(i)
            return true
        end
    end

    -- 挂牌隔离：选中房间后可用，改的是数据，当前页重绘一次
    if data.sel ~= 0 and hit(x, y, 636, T.hint.y - 4, 108, 30) then
        local act = data.toggle_iso(data.sel)
        if act then
            o.idle = 0
            pages[o.page].enter()
            M.refresh()
            local r = data.rooms[data.sel]
            voice.say(act == "iso" and (r.name .. "已挂牌隔离") or (r.name .. "已恢复送风"), 2)
        end
        return true
    end

    -- 语音开关
    if hit(x, y, 756, T.hint.y - 4, 256, 30) then
        local on = voice.toggle()
        M.refresh()
        if on then voice.say("语音已开启", 1) end
        return true
    end

    -- 交给当前页；页面拿到的是内容区内的相对坐标
    if y >= T.body.y and y < T.body.y + T.body.h then
        local done = pages[o.page].on_touch(x, y - T.body.y)
        if done then o.idle = 0 end
        return done and true or false
    end
    return false
end

-- ==================== 构建 ====================
function M.build()
    o.page, o.now, o.idle = 1, 0, 0
    o.tClock, o.tChip, o.tStatus = 0, 0, 0

    build_bg()
    build_top()
    build_nav()
    build_pages()
    build_hint()

    draw_chip()
    draw_nav()
    M.refresh()

    -- 触摸只认按下：UP 的坐标可能已经滑到隔壁页签，抬手误触比漏触更讨厌。
    -- 状态常量必须用 airui.TP_DOWN：全局 TP_DOWN 是 tp 库导出的，
    -- PC 模拟器没有 GT911（tp.init 失败、不加载 tp 库）时它是 nil，
    -- 拿它做前置判断会让整块屏在模拟器上直接退化成只读。
    if not airui.touch_subscribe then
        log.warn("clean", "固件无 airui.touch_subscribe，面板只读")
    else
        local tp_down = airui.TP_DOWN or 1     -- 1 = AIRUI_TOUCH_STATE_DOWN
        local ok = airui.touch_subscribe(function(state, tx, ty)
            if state ~= tp_down then return end
            M.on_touch(tx, ty)
        end)
        if ok then
            log.info("clean", "触摸已订阅，state=" .. tostring(tp_down))
        else
            log.error("clean", "touch_subscribe 失败，屏幕不可点")
        end
    end

    log.info("clean", "多页面控制台构建完成", T.screen.w, T.screen.h, #pages .. " 页")
end

function M.update(dt)
    data.tick(dt, T.perf.demo_speed)
    o.now = o.now + dt

    local ms = dt * 1000
    o.tChip = o.tChip + ms
    o.tStatus = o.tStatus + ms

    if o.tChip >= 500 then o.tChip = 0; draw_chip() end
    if o.tStatus >= 250 then
        o.tStatus = 0
        local s = data.state
        kit.put(o.clock, os.date("%H:%M:%S"), o, "clk")
        kit.put(o.gradeState, fmt("%d / 2", s.at_grade), o, "grade")
        kit.put(o.overState, s.over > 0 and fmt("%d 间", s.over) or "0", o, "over")
        kit.tint(o.overState, s.over > 0 and c.alarm or c.txt, o, "overc")
    end

    o.idle = o.idle + dt
    pages[o.page].update(dt, o.idle, o.now)
end

return M
