--[[
@module  dashboard
@summary 冷链温控中枢 - 主界面（温度曲线 / 温区矩阵 / 事件流 / KPI / 汇总）
@version 1.0
@date    2026.11.08
@board   Air8607 + 1024x600 RGB 屏 + GT911 触摸

=== 这块屏要回答三个问题 ===
1、现在八个温区各自多少度、有没有越界        -> 温区矩阵（一眼扫八个格子）
2、某个温区今天是怎么走过来的、什么时候开的门 -> 温度曲线（选中温区 24h）
3、刚才发生了什么、还有谁没确认              -> 事件流（最新 6 条，点一下确认）

=== 图层与重绘节奏 ===
静态层（开机画一次）：背景色带、顶栏分隔线、卡片底、标题文字、温区名牌
动态层（分区重绘，互不牵连）：
  温区矩阵  500ms  读数 + 冷量刻度 + 门开指示
  事件流    500ms  新事件插入后重排前 6 条
  曲线      1s     24h 实测 + 设定带 + 当前光点
  文字      250ms  节流，避免每帧几十次 set_text 触发 LVGL 重排

=== 触摸热区（1024x600 绝对坐标）===
  温区砖块  第一次点 = 选中（曲线跟随）；再点同一块 = 开 / 关闭库门（演示）
  曲线卡"除霜"胶囊 = 对选中温区触发一次除霜
  事件行任意一条 = 确认该条（变灰），卡头"全部确认"一次清掉
  12 秒无人操作后自动轮播温区（展厅模式）
]]

local T = require "theme"
local fx = require "fx"
local kit = require "kit"
local data = require "cold_data"
local voice = require "voice"

local M = {}
local c, f = T.c, T.f
local o = {}

-- 触摸状态常量按 C 层枚举兜底：某些固件没导出 TP_DOWN 时直接比较 nil 会让整屏点不动
local TP_DOWN = airui.TP_DOWN or 1
local L, CE, R = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT

local function f1(v) return string.format("%.1f", v) end
local function f2(v) return string.format("%.2f", v) end
local function i0(v) return string.format("%d", math.floor(v + 0.5)) end

local function hit(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

-- 温度状态 -> 颜色：正常冷蓝、接近阈值暖橙、超温报警红
local function tcolor(st)
    if st == 2 then return c.alarm end
    if st == 1 then return c.warm end
    return c.cold
end

-- ==================== 根容器与背景 ====================
local function build_bg()
    o.root = airui.container({
        x = 0, y = 0, w = T.screen.w, h = T.screen.h,
        color = c.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    -- 背景是"顶部略亮、底部沉下去"的竖向色带：12 条 50px 高的矩形，
    -- 相邻条重叠 1px，否则低色深下一眼能看见接缝
    local P = fx.pool()
    for i = 0, 11 do
        P:box(0, i * 50, T.screen.w, 51, fx.mix(0x0B1A26, 0x04080E, i / 11), 255)
    end
    P:line(0, 56, T.screen.w, 56, c.line, 1, 180)

    -- 底部汇总条每格顶上的彩条
    local cols = { c.cold, c.pur, c.warm, c.alarm, c.ok }
    for i = 1, 5 do
        local x = T.stat.x + (i - 1) * (T.stat.w + T.stat.gap)
        P:box(x, T.stat.y, T.stat.w, 3, cols[i], 200, 2)
    end

    local bg = airui.shape({ parent = o.root, x = 0, y = 0, w = T.screen.w, h = T.screen.h })
    bg:set_items(P:finish())
    o.bgShape = bg
end

-- ==================== 顶栏 ====================
local function build_top()
    -- 运行状态胶囊要随报警数变色，单独一张小画布
    o.chipShape = airui.shape({ parent = o.root, x = 812, y = 4, w = 204, h = 46 })
    o.pChip = fx.pool()

    kit.text(o.root, 20, 8, 240, 26, 20, c.txt, L, "冷链温控中枢")
    kit.text(o.root, 20, 35, 240, 14, f.mini, c.dim2, L, "COLD CHAIN CONTROL")

    o.st = {}
    local xs = { 268, 388, 508 }
    local names = { "制冷机组", "库门状态", "温度越界" }
    for i = 1, 3 do
        kit.text(o.root, xs[i], 11, 108, 14, f.mini, c.dim, L, names[i])
        o.st[i] = kit.text(o.root, xs[i], 29, 108, 17, f.body, c.txt, L, "--")
    end

    o.lbClock = kit.text(o.root, 660, 6, 132, 32, 26, c.txt, L, "09:00")
    o.lbDate = kit.text(o.root, 660, 37, 132, 14, f.mini, c.dim2, L, "--")

    o.lbMode = kit.text(o.root, 820, 14, 188, 20, f.sub, c.txt, CE, "运行正常")
    o.lbSync = kit.text(o.root, 820, 40, 188, 14, f.mini, c.dim2, R, "本地采集 2s")
end

-- ==================== KPI 四块 ====================
local KPI = {
    { name = "平均库温",   color = c.cold },
    { name = "压缩机负载", color = c.pur },
    { name = "今日能耗",   color = c.warm },
    { name = "活动报警",   color = c.alarm },
}

local function build_kpi()
    o.kpi = {}
    for i = 1, 4 do
        local x = T.kpi.x + (i - 1) * (T.kpi.w + T.kpi.gap)
        local r = { x = x, y = T.kpi.y, w = T.kpi.w, h = T.kpi.h }
        local card = kit.card(o.root, r, KPI[i].color)
        local shape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
        o.kpi[i] = {
            card = card, shape = shape, pool = fx.pool(), color = KPI[i].color,
            lbName = kit.text(card, 14, 9, 160, 15, f.mini, c.dim, L, KPI[i].name),
            lbVal = kit.text(card, 13, 24, 128, 34, f.big, KPI[i].color, L, "0"),
            lbUnit = kit.text(card, 141, 40, 46, 16, f.mini, c.dim2, L, "C"),
            lbSub = kit.text(card, 14, 60, 216, 14, f.mini, c.dim2, L, ""),
        }
    end
end

-- ==================== 曲线卡 ====================
local function build_curve()
    local r, p = T.curve, T.plot
    local card = kit.card(o.root, r, c.cold)
    o.curveShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pCurve = fx.pool()
    kit.head(card, "温度曲线 24h", 160)

    -- "除霜"胶囊：底色与描边画在 shape 里，文字在这里
    o.lbDefrost = kit.text(card, 250, 11, 52, 18, f.mini, c.dim, CE, "除霜")
    o.lbZone = kit.text(card, 306, 11, 66, 18, f.mini, c.cold, R, "")

    o.lbLegend1 = kit.text(card, 46, 38, 62, 16, f.mini, c.dim, L, "实测")
    o.lbLegend2 = kit.text(card, 128, 38, 62, 16, f.mini, c.dim, L, "设定")
    o.lbNow = kit.text(card, 200, 38, 172, 16, f.mini, c.txt, R, "")

    -- Y 轴四档刻度
    o.yAxis = {}
    for i = 0, 3 do
        o.yAxis[i + 1] = kit.text(card, 0, p.y + p.h * i / 3 - 8, p.x - 8, 14, f.mini, c.dim2, R, "")
    end
    -- X 轴五档刻度（0/6/12/18/24 时）
    o.xAxis = {}
    for i = 1, 5 do
        local x = p.x + p.w * (i - 1) / 4
        o.xAxis[i] = kit.text(card, x - 14, p.y + p.h + 5, 28, 14, f.mini, c.dim2, CE, "")
    end

    o.lbFootL = kit.text(card, p.x, 285, 180, 16, f.mini, c.dim, L, "")
    o.lbFootR = kit.text(card, 200, 285, 172, 16, f.mini, c.dim2, R, "")
end

-- ==================== 温区矩阵 ====================
local function build_zones()
    local r, t = T.zones, T.tile
    local card = kit.card(o.root, r, c.cold)
    o.zoneShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pZone = fx.pool()
    o.zoneCard = card
    kit.head(card, "温区矩阵", 150)
    kit.tag(card, 168, 12, 148, "点选中 / 再点开关门", c.dim2)

    o.tiles = {}
    for i = 1, data.NZONE do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = t.x + col * (t.w + t.gapx)
        local y = t.y + row * (t.h + t.gapy)
        local z = data.zones[i]
        o.tiles[i] = {
            x = x, y = y,
            name = kit.text(card, x + 10, y + 4, 92, 14, f.mini, c.dim, L, z.name),
            temp = kit.text(card, x + 10, y + 18, 104, 30, f.val, z.color, L, ""),
            prod = kit.text(card, x + 10, y + 47, 62, 13, f.mini, c.dim2, L, z.product),
            door = kit.text(card, x + 74, y + 47, 56, 13, f.mini, c.warm, R, ""),
        }
    end
end

-- ==================== 事件流 ====================
local NEVENT_ROW = 6

local function build_event()
    local r, er = T.event, T.event_row
    local card = kit.card(o.root, r, c.alarm)
    o.eventShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pEvent = fx.pool()
    o.eventCard = card
    kit.head(card, "事件流", 120)
    o.lbAck = kit.text(card, 140, 11, 110, 18, f.mini, c.dim2, R, "全部确认")

    o.evRows = {}
    for i = 1, NEVENT_ROW do
        local y = er.y + (i - 1) * (er.h + er.gap)
        o.evRows[i] = {
            y = y,
            time = kit.text(card, er.x + 14, y + 1, 58, 14, f.mini, c.dim2, L, ""),
            text = kit.text(card, er.x + 14, y + 15, er.w - 22, 18, f.sub, c.txt, L, ""),
        }
    end
    o.lbEvEmpty = kit.text(card, 12, 150, 240, 18, f.sub, c.dim2, CE, "暂无事件")
end

-- ==================== 底部汇总 ====================
local STAT = {
    { name = "今日能耗",   color = c.cold,  unit = "kWh" },
    { name = "压缩机峰值", color = c.pur,   unit = "% 负载" },
    { name = "开门次数",   color = c.warm,  unit = "次 今日" },
    { name = "超温次数",   color = c.alarm, unit = "次 今日" },
    { name = "今日电费",   color = c.ok,    unit = "元 含节能" },
}

local function build_stats()
    o.stats = {}
    for i = 1, 5 do
        local x = T.stat.x + (i - 1) * (T.stat.w + T.stat.gap)
        local r = { x = x, y = T.stat.y, w = T.stat.w, h = T.stat.h }
        local card = kit.card(o.root, r, nil)
        o.stats[i] = {
            name = kit.text(card, 14, 10, 160, 15, f.mini, c.dim, L, STAT[i].name),
            val = kit.text(card, 14, 27, 120, 28, f.num, STAT[i].color, L, "0"),
            unit = kit.text(card, 14, 56, 168, 14, f.mini, c.dim2, L, STAT[i].unit),
        }
    end
end

local HINT_DEFAULT = "点温区选中看曲线，再点开关库门；点事件行确认报警，点右下角开关语音"

local function build_hint()
    o.lbHint = kit.text(o.root, 14, 561, 560, 16, f.mini, c.dim2, L, HINT_DEFAULT)
    o.lbSpeed = kit.text(o.root, 576, 561, 128, 16, f.mini, c.dim2, R, "演示 40x")

    -- 静音键：一张 44x28 小画布画喇叭，右边跟一行状态文字，整块都是热区
    o.voiceShape = airui.shape({ parent = o.root, x = 706, y = 556, w = 44, h = 28 })
    o.pVoice = fx.pool()
    o.lbVoice = kit.text(o.root, 750, 561, 262, 16, f.mini, c.dim2, L, "语音开  点此静音")
end

--[[右下角语音开关的图标
开：喇叭 + 一道声波（绿）；关：喇叭 + 红斜杠；不可用：灰斜杠。静态层一次画完。]]
local function draw_voice_btn()
    local P = o.pVoice
    if not P then return end
    P:reset()
    local on = voice.enabled() and voice.ready()
    local col = on and c.ok or c.dim2

    P:box(2, 9, 5, 10, col, 235, 1)          -- 喇叭箱体
    local xs, ys = o._vx, o._vy
    if not xs then
        xs, ys = {}, {}
        o._vx, o._vy = xs, ys
    end
    xs[1], ys[1] = 7, 14
    xs[2], ys[2] = 14, 6
    xs[3], ys[3] = 14, 22
    xs[4], ys[4] = 7, 14
    P:poly(xs, ys, 4, col, 1, 220, true)

    if on then
        P:line(18, 10, 22, 14, col, 1, 200)
        P:line(22, 14, 18, 18, col, 1, 200)
        P:line(22, 7, 27, 14, col, 1, 150)
        P:line(27, 14, 22, 21, col, 1, 150)
    elseif voice.ready() then
        P:line(3, 23, 30, 5, c.alarm, 2, 220)
    else
        P:line(3, 23, 30, 5, c.line2, 1, 160)
    end
    o.voiceShape:set_items(P:finish())

    -- PC 模拟器没有音频库，提示语要和"固件裁剪了 TTS"区分开，否则调试时容易误判
    local txt
    if not voice.ready() then
        local pc = rtos and rtos.bsp and rtos.bsp() == "PC"
        txt = pc and "PC 模拟器无语音（真机可用）" or "语音不可用（固件无 TTS）"
    elseif on then
        txt = "语音开  点此静音"
    else
        txt = "语音关  点此开启"
    end
    kit.put(o.lbVoice, txt, o, "voice")
    kit.tint(o.lbVoice, on and c.dim or c.dim2, o, "voicec")
end

-- ==================== 绘制：温区矩阵 ====================
local function draw_zones()
    local P = o.pZone
    local t = T.tile
    P:reset()

    for i = 1, data.NZONE do
        local z = data.zones[i]
        local bx, by = o.tiles[i].x, o.tiles[i].y
        local col = tcolor(z.status)
        local sel = (o.zoneSel == i)

        -- 卡底：正常态压得很暗，只有异常才整块染色 —— 常亮屏不能到处发光
        local bgc = (z.status == 0) and c.panel2 or fx.mix(c.panel2, col, 0.22)
        P:box(bx, by, t.w, t.h, bgc, 255, 6)
        P:frame(bx, by, t.w, t.h, sel and c.frost or c.line, sel and 2 or 1, sel and 210 or 120, 6)

        -- 门开：右上角一块暖色方框，扫一眼就知道哪扇门敞着
        if z.door then
            P:box(bx + t.w - 20, by + 6, 14, 14, c.warm, 40, 3)
            P:frame(bx + t.w - 20, by + 6, 14, 14, c.warm, 1, 220, 3)
        end

        -- 冷量刻度：这一格现在有多吃力
        kit.vmeter(P, bx + 122, by + 18, 5, 38, z.duty or 0, col, 0x142232)

        -- 状态点：正常绿、预警橙、超温红（超温多一圈光晕）
        local dotc = (z.status == 0) and c.ok or col
        if z.status == 2 then P:dot(bx + 126, by + 11, 6, dotc, 60) end
        P:dot(bx + 126, by + 11, 3, dotc, 240)

        if sel then
            kit.brackets(P, bx + 3, by + 3, t.w - 6, t.h - 6, c.frost, 150, 9)
        end
    end
    o.zoneShape:set_items(P:finish())
end

-- ==================== 绘制：事件流 ====================
local function draw_events()
    local P = o.pEvent
    local er = T.event_row
    P:reset()

    local list = data.events
    for i = 1, NEVENT_ROW do
        local e = list[i]
        local y = er.y + (i - 1) * (er.h + er.gap)
        P:box(er.x, y, er.w, er.h - 2, c.panel2, 210, 5)
        local lvl = e and e.level or 0
        local col = (lvl == 3) and c.alarm or ((lvl == 2) and c.warm or ((lvl == 1) and c.cold or c.dim2))
        -- 左侧那根 3px 竖条就是"严重度"，确认后自动变灰
        P:box(er.x + 4, y + 5, 3, er.h - 12, col, lvl == 0 and 90 or 235, 2)
        if lvl == 3 then
            -- 报警条目加一圈淡红描边，6 行里一眼挑得出来
            P:frame(er.x, y, er.w, er.h - 2, c.alarm, 1, 110, 5)
        end
    end
    o.eventShape:set_items(P:finish())
end

-- ==================== 绘制：温度曲线 ====================
--[[量程：以设定值为中心，上下各留 3.6 倍容差
不用"历史最大/最小值"当量程：量程每帧微调会让网格上下抖，观感很差；
而"设定值 ± 3.6 倍容差"本身就有物理含义 —— 出了这个范围，货就已经危险了。]]
local function yrange(z)
    local lo = z.target - z.tol * 3.6
    local hi = z.target + z.tol * 3.6
    return lo, hi
end

local function draw_curve()
    local P = o.pCurve
    local p = T.plot
    local z = data.zones[o.zoneSel]
    P:reset()

    local lo, hi = yrange(z)
    local function ypos(v)
        local t = (v - lo) / (hi - lo)
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
        return p.y + p.h - t * p.h
    end

    -- 除霜胶囊
    local defrosting = (z.defrost or 0) > 0
    local dc = defrosting and c.frost or c.dim
    P:frame(250, 8, 52, 22, dc, 1, 180, 11)
    if defrosting then P:box(250, 8, 52, 22, c.frost, 40, 11) end

    -- 图例色点
    P:dot(34, 46, 4, tcolor(z.status), 235)
    P:dash(116, 46, 136, 46, c.dim, 1, 190, 4, 4)

    -- 网格（横向 4 档、竖向 4 档）
    for i = 0, 3 do
        local y = p.y + p.h * i / 3
        P:line(p.x, y, p.x + p.w, y, c.line2, 1, (i == 3) and 100 or 40)
    end
    for i = 0, 4 do
        local x = p.x + p.w * i / 4
        P:line(x, p.y, x, p.y + p.h, c.line2, 1, 40)
    end

    -- 容差带：设定值 ±tol 之内是"安全区"，淡色铺底
    local yTop, yBot = ypos(z.target + z.tol), ypos(z.target - z.tol)
    P:box(p.x, yTop, p.w, yBot - yTop, c.ok, 16, 0)
    -- 设定线
    local ys = ypos(z.target)
    P:dash(p.x, ys, p.x + p.w, ys, c.ok, 1, 150, 5, 5)

    -- 24h 实测曲线：已发生实线，未发生压暗（历史模型给的"预期走势"）
    local idx = data.now_index()
    local arr = data.hist[o.zoneSel]
    local N = data.NPT
    local xs, ysx = o._cx, o._cy
    if not xs then
        xs, ysx = {}, {}
        o._cx, o._cy = xs, ysx
    end
    local n, last = 0, 0
    local function put(i)
        n = n + 1
        last = i
        xs[n] = p.x + (i - 1) * p.w / (N - 1)
        ysx[n] = ypos(arr[i] or z.target)
    end
    for i = 1, idx, 2 do put(i) end
    if last ~= idx then put(idx) end
    P:poly(xs, ysx, n, tcolor(z.status), 2, 235, true)

    n = 0
    for i = idx, N, 2 do put(i) end
    if last ~= N then put(N) end
    P:poly(xs, ysx, n, tcolor(z.status), 2, 60, true)

    -- 当前时刻：竖虚线 + 光点
    local xn = p.x + (idx - 1) * p.w / (N - 1)
    P:dash(xn, p.y, xn, p.y + p.h, c.txt, 1, 60, 4, 4)
    local yn = ypos(z.temp)
    P:dot(xn, yn, 7, tcolor(z.status), 45)
    P:dot(xn, yn, 3.5, tcolor(z.status), 255)

    -- 越界告警线：上沿超出去的时候在最顶上压一条红
    if z.temp > z.target + z.tol * 2 then
        P:box(p.x, p.y - 3, p.w, 3, c.alarm, 220, 1)
    end

    o.curveShape:set_items(P:finish())
end

-- ==================== 绘制：KPI / 顶栏胶囊 ====================
local KPI_MAX = { 40, 100, 120, 6 }   -- 平均温度按 |C| 最大 40 归一、能耗按 120kWh 归一

local function draw_kpi()
    local s, td = data.state, data.today
    local vals = { math.abs(s.avg), s.comp, td.kwh, data.active_alarms() }
    for i = 1, 4 do
        local k = o.kpi[i]
        local P = k.pool
        P:reset()
        kit.meter(P, 13, 74, 216, 4, fx.clamp(vals[i] / KPI_MAX[i], 0, 1), k.color, 0x142232)
        k.shape:set_items(P:finish())
    end
end

local function draw_chips()
    local P = o.pChip
    P:reset()
    local alarms = data.active_alarms()
    local over = data.count_status(2)
    local col
    if alarms > 0 then
        col = c.alarm
        P:box(6, 8, 192, 28, col, 32, 14)
        P:frame(6, 8, 192, 28, col, 1, 170, 14)
        P:dot(18, 22, 3, col, 235)
    else
        col = c.ok
        P:box(6, 8, 192, 28, col, 22, 14)
        P:frame(6, 8, 192, 28, col, 1, 110, 14)
        P:dot(18, 22, 3, col, 235)
    end
    o.chipShape:set_items(P:finish())
    o._chipCol = col
    o._chipOver = over
end

-- ==================== 文字刷新 ====================
local HINTS = {
    "点温区选中看曲线，再点开关库门；点事件行确认报警，点右下角开关语音",
    "温区格右下角那块暖色方块代表库门开着，超过 90 秒会记一条事件",
    "曲线里的绿带是设定值的容差范围，出了带子就是该去看一眼了",
    "曲线卡右上角“除霜”对当前选中的温区生效，除霜期间温度会短时上浮",
    "12 秒不动屏幕，温区会自动轮播，方便挂在大厅当看板",
}

local function refresh_text()
    local s, td = data.state, data.today

    kit.put(o.lbClock, data.clock_str(), o, "clk")

    local d = os.date("*t")
    if d and d.year >= 2020 then
        kit.put(o.lbDate, string.format("%04d-%02d-%02d", d.year, d.month, d.day), o, "date")
    else
        kit.put(o.lbDate, "未校时 演示时钟", o, "date")
    end

    -- 顶栏三路状态
    local open_n, over_n = 0, 0
    for i = 1, data.NZONE do
        if data.zones[i].door then open_n = open_n + 1 end
    end
    over_n = data.count_status(2)
    kit.put(o.st[1], (s.comp > 12) and (i0(s.comp) .. "% 运行中") or "待机", o, "st1")
    kit.put(o.st[2], (open_n > 0) and (i0(open_n) .. " 扇开启") or "全部关闭", o, "st2")
    kit.put(o.st[3], (over_n > 0) and (i0(over_n) .. " 区超温") or "无越界", o, "st3")
    kit.tint(o.st[2], open_n > 0 and c.warm or c.txt, o, "st2c")
    kit.tint(o.st[3], over_n > 0 and c.alarm or c.txt, o, "st3c")

    local alarms = data.active_alarms()
    kit.put(o.lbMode, alarms > 0 and string.format("报警 %d 条待确认", alarms) or "系统运行正常", o, "mode")
    kit.tint(o.lbMode, alarms > 0 and c.alarm or c.ok, o, "modec")
    kit.put(o.lbSync, string.format("采集 2s  仿真 %dx", T.perf.demo_speed), o, "sync")

    -- KPI
    local k1, k2, k3, k4 = o.kpi[1], o.kpi[2], o.kpi[3], o.kpi[4]
    local ok_n, warn_n = data.count_status(0), data.count_status(1)
    kit.put(k1.lbVal, f1(s.avg), o, "k1v")
    kit.put(k1.lbUnit, "C", o, "k1u")
    kit.put(k1.lbSub, string.format("正常 %d  预警 %d  超温 %d", ok_n, warn_n, over_n), o, "k1s")

    kit.put(k2.lbVal, i0(s.comp), o, "k2v")
    kit.put(k2.lbUnit, "%", o, "k2u")
    kit.put(k2.lbSub, string.format("今日峰值 %d%%  8 台机组", math.floor(td.peak + 0.5)), o, "k2s")

    kit.put(k3.lbVal, f1(td.kwh), o, "k3v")
    kit.put(k3.lbUnit, "kWh", o, "k3u")
    kit.put(k3.lbSub, string.format("%s 元  省 %.1f%%", f2(data.cost()), td.save), o, "k3s")

    kit.put(k4.lbVal, i0(alarms), o, "k4v")
    kit.put(k4.lbUnit, "条", o, "k4u")
    kit.put(k4.lbSub, alarms > 0 and "点事件行可逐条确认" or "无待确认事件", o, "k4s")
    kit.tint(k4.lbVal, alarms > 0 and c.alarm or c.ok, o, "k4c")

    -- 曲线卡的坐标刻度随时间/量程变化
    local z = data.zones[o.zoneSel]
    local lo, hi = yrange(z)
    for i = 0, 3 do
        kit.put(o.yAxis[i + 1], f1(hi - (hi - lo) * i / 3), o, "y" .. i)
    end
    for i = 1, 5 do
        kit.put(o.xAxis[i], string.format("%d", (i - 1) * 6), o, "x" .. i)
    end
    kit.put(o.lbZone, z.name, o, "zsel")
    kit.tint(o.lbZone, tcolor(z.status), o, "zselc")
    kit.put(o.lbNow, string.format("当前 %sC  偏差 %+.1f", f1(z.temp), z.temp - z.target), o, "now")
    kit.put(o.lbFootL, string.format("设定 %sC  容差 %.1fC", f1(z.target), z.tol), o, "footl")
    kit.put(o.lbFootR, string.format("%s  今日开门 %d 次", z.product, td.doors), o, "footr")
    kit.put(o.lbDefrost, (z.defrost or 0) > 0 and "除霜中" or "除霜", o, "def")
    kit.tint(o.lbDefrost, (z.defrost or 0) > 0 and c.frost or c.dim, o, "defc")

    -- 温区砖块：读数 + 门状态
    for i = 1, data.NZONE do
        local tz = data.zones[i]
        local tile = o.tiles[i]
        kit.put(tile.temp, f1(tz.temp), o, "t" .. i)
        kit.tint(tile.temp, tcolor(tz.status), o, "tc" .. i)
        kit.put(tile.door, tz.door and "开门" or ((tz.defrost or 0) > 0 and "除霜" or ""), o, "td" .. i)
    end

    -- 事件流：前 6 条，时间 + 文本 + 严重度配色
    for i = 1, NEVENT_ROW do
        local e = data.events[i]
        local row = o.evRows[i]
        if e then
            local lvl = e.level
            local col = (lvl == 3) and c.alarm or ((lvl == 2) and c.warm or ((lvl == 1) and c.txt or c.dim2))
            kit.put(row.time, e.t, o, "et" .. i)
            kit.put(row.text, (lvl == 0) and ("已确认  " .. e.text) or e.text, o, "ex" .. i)
            kit.tint(row.text, col, o, "exc" .. i)
            kit.tint(row.time, lvl == 0 and c.dim2 or c.dim, o, "etc" .. i)
        else
            kit.put(row.time, "", o, "et" .. i)
            kit.put(row.text, "", o, "ex" .. i)
        end
    end
    kit.put(o.lbEvEmpty, (#data.events == 0) and "暂无事件" or "", o, "evempty")
    kit.tint(o.lbAck, (data.active_alarms() > 0) and c.dim or c.dim2, o, "ackc")

    -- 底部汇总
    kit.put(o.stats[1].val, f1(td.kwh), o, "s1")
    kit.put(o.stats[2].val, i0(td.peak), o, "s2")
    kit.put(o.stats[3].val, i0(td.doors), o, "s3")
    kit.put(o.stats[4].val, i0(td.over), o, "s4")
    kit.put(o.stats[5].val, f1(data.cost()), o, "s5")

    -- 提示行轮换：每 9 秒换一句，别让同一句话在屏上挂一整天
    -- 用仿真时间而不是 os.time：没校时的板子上 os.time 恒为 0，提示行会永远停在第一句
    local k = math.floor(data.state.sim_t / 9) % #HINTS + 1
    kit.put(o.lbHint, HINTS[k], o, "hint")
end

-- ==================== 交互 ====================
local function say(txt)
    voice.say(txt)
end
M.say = say

--[[选中一个温区
@param number i 温区下标
@param boolean quiet 静默（自动轮播时用，不播报）]]
local function focus_zone(i, quiet)
    i = ((i - 1) % data.NZONE) + 1
    o.zoneSel = i
    o.zoneDirty = true
    if quiet then return end
    local z = data.zones[i]
    say(string.format("%s，当前 %s 度", z.name, f1(z.temp)))
end
M.focus_zone = focus_zone

local function on_press(x, y)
    o.idle = 0

    -- 语音开关（右下角整块，含文字）
    if hit(x, y, 700, 550, 312, 44) then
        local on = voice.toggle()
        draw_voice_btn()
        if on then say("语音已开启") end
        return true
    end

    -- 除霜胶囊
    if hit(x, y, T.curve.x + 250, T.curve.y + 8, 52, 22) then
        local z = data.zones[o.zoneSel]
        if data.start_defrost(o.zoneSel) then
            say(z.name .. " 开始除霜，约十三分钟")
        else
            say(z.name .. " 正在除霜，请稍候")
        end
        o.curveDirty, o.zoneDirty, o.textT = true, true, 999
        return true
    end

    -- 事件卡头"全部确认"
    if hit(x, y, T.event.x + 140, T.event.y + 11, 110, 20) then
        local n = data.ack_all()
        say(n > 0 and string.format("已确认 %d 条事件", n) or "没有待确认事件")
        o.evDirty, o.textT = true, 999
        return true
    end

    -- 事件行：逐条确认
    local er = T.event_row
    for i = 1, NEVENT_ROW do
        local ry = T.event.y + er.y + (i - 1) * (er.h + er.gap)
        if hit(x, y, T.event.x + er.x, ry, er.w, er.h - 2) then
            local e = data.events[i]
            if not e then return true end
            if data.ack_event(i) then
                say("已确认，" .. e.text)
            else
                say("这条已经确认过了")
            end
            o.evDirty, o.textT = true, 999
            return true
        end
    end

    -- 温区砖块：第一次点选中，再点同一块开关门
    local t = T.tile
    for i = 1, data.NZONE do
        local bx = T.zones.x + o.tiles[i].x
        local by = T.zones.y + o.tiles[i].y
        if hit(x, y, bx, by, t.w, t.h) then
            if o.zoneSel == i then
                local open = data.toggle_door(i)
                local z = data.zones[i]
                say(open and (z.name .. " 库门已打开") or (z.name .. " 库门已关闭"))
                o.zoneDirty, o.curveDirty, o.textT = true, true, 999
            else
                focus_zone(i)
            end
            return true
        end
    end
    return false
end
M.on_press = on_press

local function on_touch(state, x, y)
    -- 只认按下：抬起点也能触发会让"点一下就选中"变两次（选中后又当成开关门）
    if state ~= TP_DOWN then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local ok, err = pcall(on_press, x, y)
    if not ok then log.warn("cold", "触摸处理异常", err) end
end

-- ==================== 组装与生命周期 ====================
function M.build()
    build_bg()
    build_top()
    build_kpi()
    build_curve()
    build_zones()
    build_event()
    build_stats()
    build_hint()

    o.zoneSel = 1
    o.idle = 0
    o.zoneDirty, o.evDirty, o.curveDirty = true, true, true
    o.tileT, o.evT, o.curveT, o.textT = 0, 0, 0, 0

    draw_voice_btn()
    draw_zones()
    draw_events()
    draw_curve()
    draw_kpi()
    draw_chips()
    refresh_text()

    airui.touch_subscribe(on_touch)
    log.info("cold", "界面构建完成", T.screen.w, T.screen.h)
end

--[[按帧推进：数据照常走，视图按各自节流周期重绘
@param number dt 距上一帧的秒数]]
function M.update(dt)
    o.tileT = o.tileT + dt * 1000
    o.evT = o.evT + dt * 1000
    o.curveT = o.curveT + dt * 1000
    o.idle = o.idle + dt

    -- 无人操作自动轮播：展厅/值班室里屏会长时间没人碰
    if o.idle > T.perf.auto_zone_sec then
        o.idle = T.perf.auto_zone_sec - 4     -- 停 4 秒再轮下一个，别转得太急
        focus_zone(o.zoneSel + 1, true)
    end

    if o.tileT >= T.perf.tile_ms or o.zoneDirty then
        o.tileT = 0
        o.zoneDirty = false
        draw_zones()
    end
    if o.evT >= T.perf.event_ms or o.evDirty then
        o.evT = 0
        o.evDirty = false
        draw_events()
    end
    if o.curveT >= T.perf.curve_ms or o.curveDirty then
        o.curveT = 0
        o.curveDirty = false
        draw_curve()
    end
    if kit.hot(o, dt) then
        draw_kpi()
        draw_chips()
        refresh_text()
    end
end

function M.root()
    return o.root
end

return M
