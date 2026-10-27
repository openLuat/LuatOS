--[[
@module  dashboard
@summary 家庭能源监测面板 - 主界面（能源流向 / 今日曲线 / 分路排行 / KPI / 汇总）
@version 1.0
@date    2026.10.26
@board   Air8607 + 1024x600 RGB 屏 + GT911 触摸

=== 这块屏要回答三个问题 ===
1、现在家里在用什么、用多少            -> 顶栏 + KPI 四块 + 流向图中心节点
2、这些电从哪来、有没有花钱            -> 能源流向图（光伏 / 电网 / 储能 三条链路）
3、今天整体怎么样、哪个电器最费电      -> 今日曲线 + 分路排行榜 + 底部汇总

=== 图层与重绘节奏 ===
静态层（开机画一次）：背景色带、顶栏分隔线、卡片底、所有标题文字
动态层（分区重绘，互不牵连）：
  流向图  66ms   光点沿三条链路跑，节点亮度随功率变
  曲线    1s     今日已发生部分实线，未来预测部分压暗
  分路条  500ms  按当前功率从大到小排序
  文字    250ms  节流，避免每帧几十次 set_text 触发 LVGL 重排

=== 触摸热区（1024x600 绝对坐标）===
  储能节点 -> 循环切换储能策略；光伏/电网/家庭节点 -> 底部提示行播报详情
  曲线卡的 日/周/月 胶囊 -> 切换统计粒度
  分路卡任意一行 -> 开关该路电器（模拟智能断路器），曲线与排行同步重算
  12 秒无人操作后曲线自动轮播（展厅模式）
]]

local T = require "theme"
local fx = require "fx"
local kit = require "kit"
local data = require "energy_data"
local voice = require "voice"

local M = {}
local c, f = T.c, T.f
local o = {}

-- 触摸状态常量按 C 层枚举兜底：某些固件没导出 TP_DOWN 时直接比较 nil 会让整屏点不动
local TP_DOWN = airui.TP_DOWN or 1

local function f2(v) return string.format("%.2f", v) end
local function f1(v) return string.format("%.1f", v) end
local function i0(v) return string.format("%d", math.floor(v + 0.5)) end

local function hit(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
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
        P:box(0, i * 50, T.screen.w, 51, fx.mix(0x0B1524, 0x05090F, i / 11), 255)
    end
    P:line(0, 56, T.screen.w, 56, c.line, 1, 180)

    -- 顶栏三个设备状态点（静态色，在线与否由右侧文字表达）
    local dots = { { 250, c.solar }, { 370, c.grid }, { 490, c.batt } }
    for i = 1, 3 do
        P:dot(dots[i][1], 19, 3, dots[i][2], 210)
        P:dot(dots[i][1], 19, 6, dots[i][2], 40)
    end

    -- 底部汇总条每格顶上的彩条
    local cols = { c.home, c.solar, c.ok, c.buy, c.ok }
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
    -- 电价 / 并网两个胶囊要随峰谷变色，单独一张小画布
    o.chipShape = airui.shape({ parent = o.root, x = 790, y = 4, w = 226, h = 46 })
    o.pChip = fx.pool()

    kit.text(o.root, 20, 8, 240, 26, 20, c.txt, airui.TEXT_ALIGN_LEFT, "家庭能源监测")
    kit.text(o.root, 20, 35, 240, 14, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "HOME ENERGY MONITOR")

    o.st = {}
    local xs = { 260, 380, 500 }
    local names = { "光伏逆变器", "智能电表", "储能电池" }
    for i = 1, 3 do
        kit.text(o.root, xs[i], 11, 108, 14, f.mini, c.dim, airui.TEXT_ALIGN_LEFT, names[i])
        o.st[i] = kit.text(o.root, xs[i], 29, 108, 17, f.body, c.txt, airui.TEXT_ALIGN_LEFT, "--")
    end

    o.lbClock = kit.text(o.root, 656, 6, 124, 32, 26, c.txt, airui.TEXT_ALIGN_LEFT, "09:12")
    o.lbDate = kit.text(o.root, 656, 37, 124, 14, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "--")

    o.lbPrice = kit.text(o.root, 798, 15, 104, 20, f.sub, c.txt, airui.TEXT_ALIGN_CENTER, "峰段 0.62")
    o.lbGrid = kit.text(o.root, 910, 15, 94, 20, f.sub, c.txt, airui.TEXT_ALIGN_CENTER, "并网")
    o.lbSync = kit.text(o.root, 790, 40, 226, 14, f.mini, c.dim2, airui.TEXT_ALIGN_RIGHT, "本地采集 1s")
end

-- ==================== KPI 四块 ====================
local KPI = {
    { name = "家庭负载", color = c.home },
    { name = "光伏发电", color = c.solar },
    { name = "电网交互", color = c.grid },
    { name = "储能电池", color = c.batt },
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
            lbName = kit.text(card, 14, 9, 160, 15, f.mini, c.dim, nil, KPI[i].name),
            lbVal = kit.text(card, 13, 24, 120, 34, f.big, KPI[i].color, nil, "0.00"),
            lbUnit = kit.text(card, 133, 40, 52, 16, f.mini, c.dim2, nil, "kW"),
            lbSub = kit.text(card, 14, 60, 216, 14, f.mini, c.dim2, nil, ""),
        }
    end
end

-- ==================== 能源流向卡 ====================
local function build_flow()
    local r, n = T.flow, T.node
    local card = kit.card(o.root, r, nil)
    o.flowShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pFlow = fx.pool()

    kit.head(card, "能源流向", 200)
    o.flowTag = kit.tag(card, 226, 10, 98, "实时", c.dim2)

    local L, C, R = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT
    o.fv = {
        pvName = kit.text(card, n.pv.x - 44, 116, 88, 15, f.mini, c.dim, C, "光伏"),
        pvVal = kit.text(card, n.pv.x - 46, 131, 92, 19, f.sub, c.solar, C, "0.00kW"),
        btName = kit.text(card, n.batt.x - 44, 116, 88, 15, f.mini, c.dim, C, "储能"),
        btVal = kit.text(card, n.batt.x - 46, 131, 92, 19, f.sub, c.batt, C, "0.00kW"),
        btMode = kit.text(card, n.batt.x - 50, 151, 100, 14, f.mini, c.dim2, C, "自发自用"),
        gdName = kit.text(card, n.grid.x + 36, 228, 110, 15, f.mini, c.dim, L, "电网"),
        gdVal = kit.text(card, n.grid.x + 36, 244, 110, 20, f.sub, c.grid, L, "0.00kW"),
        hmVal = kit.text(card, n.home.x - 58, 124, 116, 26, f.val, c.txt, C, "0.00"),
        hmSub = kit.text(card, n.home.x - 58, 152, 116, 14, f.mini, c.dim2, C, "当前总功率 kW"),
        ftName = kit.text(card, 12, 277, 120, 15, f.mini, c.dim, L, "能源自给率"),
        ftVal = kit.text(card, 250, 275, 74, 19, f.val, c.ok, R, "0%"),
    }
end

-- ==================== 曲线卡 ====================
local SEG = { "日", "周", "月" }
-- 语音专用的说法：屏上"周"是一个字够用，念出来"切换到周"听着像半句话
local SEG_SAY = { "今天", "这一周", "这一个月" }
-- 电价时段同理："平段"是电力行业的写法，得补成"平时段"才像人话
local SEG_NAME = { ["平"] = "平时段", ["峰"] = "峰时段", ["谷"] = "谷时段" }

local function build_chart()
    local r, p = T.chart, T.plot
    local L, C, R = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT
    local card = kit.card(o.root, r, nil)
    o.chartShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pChart = fx.pool()
    kit.head(card, "功率曲线", 150)

    -- 日/周/月 胶囊：底色画在 shape 里（要随选中态变），文字在这里
    o.segLb = {}
    for i = 1, 3 do
        -- 默认视图是"日"，第一颗胶囊直接建成就用高亮色：
        -- 否则要等第一次切视图才会亮，开机那一眼看不出哪个是选中态
        o.segLb[i] = kit.text(card, 234 + (i - 1) * 46, 10, 44, 20, f.mini,
            (i == 1) and c.txt or c.dim, C, SEG[i])
    end

    o.lbLegendLoad = kit.text(card, 30, 41, 44, 16, f.mini, c.dim, L, "用电")
    o.lbLegendPv = kit.text(card, 108, 41, 44, 16, f.mini, c.dim, L, "发电")
    o.lbPeak = kit.text(card, 196, 41, 176, 16, f.mini, c.dim2, R, "")

    -- Y 轴四档刻度（数值随量程变，文字动态）
    o.yAxis = {}
    for i = 0, 3 do
        o.yAxis[i + 1] = kit.text(card, 0, p.y + p.h * i / 3 - 8, p.x - 6, 14, f.mini, c.dim2, R, "0")
    end
    -- X 轴五档刻度（宽 28 居中，最右一档右边沿正好落在 384 卡宽内）
    o.xAxis = {}
    for i = 1, 5 do
        local x = p.x + p.w * (i - 1) / 4
        o.xAxis[i] = kit.text(card, x - 14, p.y + p.h + 6, 28, 14, f.mini, c.dim2, C, "")
    end

    o.lbFootL = kit.text(card, p.x, 285, 168, 16, f.mini, c.dim, L, "")
    o.lbFootR = kit.text(card, 196, 285, 174, 16, f.mini, c.dim2, R, "")
end

-- ==================== 分路卡 ====================
local function build_circ()
    local r = T.circ
    local L, R = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_RIGHT
    local card = kit.card(o.root, r, nil)
    o.circShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pCirc = fx.pool()
    o.circCard = card
    kit.head(card, "分路用电", 150)
    kit.tag(card, 186, 12, 64, "触摸开关", c.dim2)

    o.rows = {}
    local row = T.circ_row
    for i = 1, data.NCIRC do
        local y = row.y + (i - 1) * (row.h + row.gap)
        o.rows[i] = {
            name = kit.text(card, 12, y + 1, 72, 15, f.mini, c.dim, L, ""),
            val = kit.text(card, 186, y + 1, 64, 15, f.mini, c.dim, R, ""),
        }
    end
    -- 行序按当前功率动态排，需要一份"第 i 行显示哪个分路"的映射
    o.rowMap = {}
    for i = 1, data.NCIRC do o.rowMap[i] = i end
end

-- ==================== 底部汇总 ====================
local STAT = {
    { name = "今日用电", color = c.home, unit = "kWh" },
    { name = "今日发电", color = c.solar, unit = "kWh" },
    { name = "能源自给", color = c.ok, unit = "自给自用比例" },
    { name = "今日电费", color = c.buy, unit = "元 含上网收益" },
    { name = "减少碳排", color = c.ok, unit = "kg CO2" },
}

local function build_stats()
    o.stats = {}
    local L = airui.TEXT_ALIGN_LEFT
    for i = 1, 5 do
        local x = T.stat.x + (i - 1) * (T.stat.w + T.stat.gap)
        local r = { x = x, y = T.stat.y, w = T.stat.w, h = T.stat.h }
        local card = kit.card(o.root, r, nil)
        o.stats[i] = {
            name = kit.text(card, 14, 10, 160, 15, f.mini, c.dim, L, STAT[i].name),
            val = kit.text(card, 14, 27, 120, 28, f.num, STAT[i].color, L, "0.0"),
            unit = kit.text(card, 14, 56, 168, 14, f.mini, c.dim2, L, STAT[i].unit),
        }
    end
end

local function build_hint()
    o.lbHint = kit.text(o.root, 14, 561, 556, 16, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT,
        "触摸分路行可开关电器，触摸储能节点切换策略，触摸曲线卡切换日/周/月")

    -- 演示倍率从"提示行右侧"挪到"顶栏采集指示"旁边，把右下角让给语音开关
    o.lbSpeed = kit.text(o.root, 576, 561, 128, 16, f.mini, c.dim2, airui.TEXT_ALIGN_RIGHT,
        "演示 60x")

    -- 静音键：一张 44x28 小画布画喇叭，右边跟一行状态文字，整块都是热区
    o.voiceShape = airui.shape({ parent = o.root, x = 706, y = 556, w = 44, h = 28 })
    o.pVoice = fx.pool()
    o.lbVoice = kit.text(o.root, 750, 561, 262, 16, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT,
        "语音开  点此静音")
end

--[[右下角语音开关的图标
开：喇叭 + 两道声波（绿）；关：喇叭 + 红斜杠。图标不做动画，静态层一次画完。]]
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
        P:line(3, 23, 30, 5, c.red, 2, 220)
    else
        P:line(3, 23, 30, 5, c.line2, 1, 160)
    end
    o.voiceShape:set_items(P:finish())

    -- PC 模拟器没有音频 C 库，提示语要和"固件裁剪了 TTS"区分开，否则调试时容易误判
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

-- ==================== 绘制：能量链路 ====================
-- 两个节点之间的连线端点（各自退到圆边上，线不会插进圆里）
local function edge(a, b)
    local dx, dy = b.x - a.x, b.y - a.y
    local d = math.sqrt(dx * dx + dy * dy)
    local ux, uy = dx / d, dy / d
    return a.x + ux * a.r, a.y + uy * a.r, b.x - ux * b.r, b.y - uy * b.r, ux, uy, d
end

--[[画一条能量链路
@param number kw 当前流过的功率（0 表示这条链路断着）
@param number dir 1 = a→b，-1 = b→a
@param number t 动画时间（秒）
链路亮度和光点速度都跟功率相关：功率越大，越亮、跑得越快 —— 这就是"看得见的功率"。
]]
local function draw_link(P, a, b, kw, dir, color, t)
    local x1, y1, x2, y2, ux, uy = edge(a, b)
    -- 底轨（断流时也能看清拓扑）
    P:line(x1, y1, x2, y2, fx.mix(c.panel, color, 0.20), 3, 255)
    local ratio = fx.clamp((kw or 0) / 4.5, 0, 1)
    if ratio < 0.02 then return end

    P:line(x1, y1, x2, y2, color, 2, 60 + 130 * ratio)
    if dir < 0 then x1, y1, x2, y2 = x2, y2, x1, y1 end

    -- 三个等距光点沿着链路跑
    local speed = 0.30 + 0.55 * ratio
    local rad = 2 + 2.0 * ratio
    for k = 1, 3 do
        local p = (t * speed + (k - 1) / 3) % 1
        local px, py = x1 + (x2 - x1) * p, y1 + (y2 - y1) * p
        P:dot(px, py, rad + 1.6, color, 26)
        P:dot(px, py, rad, color, 140 + 110 * ratio)
    end
    -- 中点箭头指明方向
    local mx, my = (x1 + x2) / 2, (y1 + y2) / 2
    fx.arrow(P, mx, my, math.atan(y2 - y1, x2 - x1), 6, color, 2, 110)
end

-- 太阳（光伏）：中心圆 + 8 根光芒
local function icon_sun(P, cx, cy, color)
    P:ring(cx, cy, 7, color, 2, 235)
    for k = 0, 7 do
        local a = k * math.pi / 4
        local ca, sa = math.cos(a), math.sin(a)
        P:line(cx + ca * 11, cy + sa * 11, cx + ca * 15.5, cy + sa * 15.5, color, 2, 200, true)
    end
end

-- 电池（储能）：外框 + 顶盖 + 按 SOC 填充的电量条
local function icon_batt(P, cx, cy, color, soc)
    local w, h = 18, 26
    local x, y = cx - w / 2, cy - h / 2
    P:frame(x, y, w, h, color, 1, 170, 3)
    P:box(cx - 3, y - 4, 6, 3, color, 170, 1)
    local fh = math.floor((h - 4) * fx.clamp(soc / 100, 0, 1))
    if fh >= 1 then P:box(x + 2, y + h - 2 - fh, w - 4, fh, color, 185, 1) end
end

-- 闪电（电网）：7 点折线勾出电 bolt 的轮廓
local bx = { 2, -7, 1, -2, 7, -1, 2 }
local by = { -12, 1, 1, 11, -1, -1, -12 }
local function icon_bolt(P, cx, cy, color)
    local xs, ys = {}, {}
    for i = 1, 7 do
        xs[i], ys[i] = cx + bx[i], cy + by[i]
    end
    P:poly(xs, ys, 7, color, 2, 230, true)
end

local function draw_node(P, n, color, bright)
    P:dot(n.x, n.y, n.r, fx.mix(c.panel, color, 0.10), 255)
    P:ring(n.x, n.y, n.r, color, 2, bright)
    P:ring(n.x, n.y, n.r + 5, color, 1, math.floor(bright * 0.22))
end

-- ==================== 绘制：流向卡 ====================
local function draw_flow()
    local P = o.pFlow
    P:reset()
    local n, s = T.node, data.state
    local t = o.anim

    local pvKw = s.pv > 0.05 and s.pv or 0
    local gdKw = math.abs(s.grid) > 0.05 and math.abs(s.grid) or 0
    local btKw = math.abs(s.bat) > 0.05 and math.abs(s.bat) or 0

    draw_link(P, n.pv, n.home, pvKw, 1, c.solar, t)
    draw_link(P, n.grid, n.home, gdKw, s.grid >= 0 and 1 or -1, c.grid, t)
    -- 电池：充电是"家里→电池"，放电是"电池→家里"
    draw_link(P, n.batt, n.home, btKw, s.bat >= 0 and -1 or 1, c.batt, t)

    -- 家庭节点外圈的 24 格负荷环：点亮几格 = 负载占到设计容量的几成
    local ratio = fx.clamp(s.load / 8.0, 0, 1)
    local lit = math.floor(ratio * 24 + 0.5)
    local lc = kit.level(ratio)
    for k = 0, 23 do
        local a = -math.pi / 2 + k * math.pi * 2 / 24
        local ca, sa = math.cos(a), math.sin(a)
        local on = k < lit
        P:line(n.home.x + ca * 45, n.home.y + sa * 45, n.home.x + ca * 50, n.home.y + sa * 50,
            on and lc or c.line2, on and 2 or 1, on and 210 or 70, true)
    end
    P:dot(n.home.x, n.home.y, n.home.r, fx.mix(c.panel, c.home, 0.10), 255)
    P:ring(n.home.x, n.home.y, n.home.r, c.home, 2, 150)
    P:ring(n.home.x, n.home.y, n.home.r + 3, c.home, 1, 40)

    icon_sun(P, n.pv.x, n.pv.y, pvKw > 0 and c.solar or c.dim2)
    icon_batt(P, n.batt.x, n.batt.y, btKw > 0 and c.batt or c.dim2, s.soc)
    icon_bolt(P, n.grid.x, n.grid.y, gdKw > 0 and c.grid or c.dim2)

    -- 自给率的底部进度条
    kit.divider(P, 12, 270, 312, c.line, 110)
    kit.meter(P, 12, 296, 312, 5, data.self_rate(), c.ok, 0x142232)

    o.flowShape:set_items(P:finish())
end

-- ==================== 绘制：KPI 与顶栏胶囊 ====================
local KPI_MAX = { 8.0, 9.0, 6.0, 100 }

local function draw_kpi()
    local s = data.state
    local vals = { s.load, s.pv, math.abs(s.grid), s.soc }
    for i = 1, 4 do
        local k = o.kpi[i]
        local P = k.pool
        P:reset()
        local frac = fx.clamp(vals[i] / KPI_MAX[i], 0, 1)
        kit.meter(P, 13, 74, 216, 4, frac, k.color, 0x142232)
        k.shape:set_items(P:finish())
    end
end

local function draw_chips()
    local P = o.pChip
    P:reset()
    local seg = data.state.seg or "平"
    local pc = (seg == "峰") and c.red or ((seg == "谷") and c.ok or c.warn)
    P:box(8, 8, 104, 28, pc, 28, 14)
    P:frame(8, 8, 104, 28, pc, 1, 150, 14)
    P:dot(18, 22, 3, pc, 230)
    local selling = data.state.grid < -0.05
    local gc = selling and c.ok or c.warn
    P:box(120, 8, 94, 28, gc, 26, 14)
    P:frame(120, 8, 94, 28, gc, 1, 130, 14)
    P:dot(130, 22, 3, gc, 230)
    o.chipShape:set_items(P:finish())
end

-- ==================== 绘制：曲线卡 ====================
local SX, SY = {}, {}   -- 折线用的复用坐标表（同一时刻只被一方使用）

--[[画一段序列（i0..i1 是数据下标，不是屏幕坐标）
@param stride 采样间隔：96 个点挤在 336px 上，每点间距 3.5px，
              隔一个点取一次肉眼分不出差别，图元数却少一半。]]
local function series(P, vals, i0, i1, p, vmax, color, width, opa, stride)
    local N = data.NPT
    local step = p.w / (N - 1)
    local n, last = 0, 0
    local function put(i)
        n = n + 1
        last = i
        SX[n] = p.x + (i - 1) * step
        SY[n] = p.y + p.h - fx.clamp(vals[i] / vmax, 0, 1) * p.h
    end
    for i = i0, i1, stride or 1 do put(i) end
    -- 末端补齐：否则"现在"那一刻的曲线会停在采样点上，跟光点错开 3px
    if last ~= i1 then put(i1) end
    P:poly(SX, SY, n, color, width, opa, true)
end

local function draw_day(P, p)
    local N, vmax = data.NPT, o.dayMax or 6
    local idx = data.now_index()

    -- 峰段底纹：08:00-11:00 与 18:00-21:00，电价贵的时候背着红色
    local bands = { { 8, 11 }, { 18, 21 } }
    for i = 1, 2 do
        P:box(p.x + p.w * bands[i][1] / 24, p.y, p.w * (bands[i][2] - bands[i][1]) / 24, p.h, c.red, 16, 0)
    end

    kit.area(P, data.day.pv, idx, p.x, p.y, p.w, p.h, vmax, c.solar, 22, 7, 2)
    series(P, data.day.load, 1, idx, p, vmax, c.home, 2, 225, 2)
    series(P, data.day.pv, 1, idx, p, vmax, c.solar, 2, 215, 2)
    if idx < N then
        -- 未来时段是预测值，压暗：让人一眼分清"已发生"和"预测"
        series(P, data.day.pv, idx, N, p, vmax, c.solar, 2, 55, 2)
        series(P, data.day.load, idx, N, p, vmax, c.home, 2, 55, 2)
    end

    -- 当前时刻：竖虚线 + 两条曲线上的光点
    local xn = p.x + (idx - 1) * p.w / (N - 1)
    P:dash(xn, p.y, xn, p.y + p.h, c.txt, 1, 70, 4, 4)
    local yl = p.y + p.h - fx.clamp(data.day.load[idx] / vmax, 0, 1) * p.h
    local yp = p.y + p.h - fx.clamp(data.day.pv[idx] / vmax, 0, 1) * p.h
    P:dot(xn, yl, 5, c.home, 60)
    P:dot(xn, yl, 2.5, c.home, 255)
    P:dot(xn, yp, 5, c.solar, 60)
    P:dot(xn, yp, 2.5, c.solar, 255)
end

local function draw_bars(P, p)
    local d = (o.view == 2) and data.week or data.month
    local n, vmax = d.n, o.barMax or 10
    local bw = p.w / n
    local sum = 0

    for i = 1, n do
        local x = p.x + (i - 1) * bw
        local hh = math.floor(fx.clamp(d.load[i] / vmax, 0, 1) * p.h + 0.5)
        local today = (i == n)
        local w = math.max(2, math.floor(bw * 0.62))
        P:box(math.floor(x + (bw - w) / 2), p.y + p.h - hh, w, hh, c.home, today and 235 or 115, 1)
        sum = sum + d.load[i]
        SX[i] = x + bw / 2
        SY[i] = p.y + p.h - fx.clamp(d.pv[i] / vmax, 0, 1) * p.h
    end
    P:poly(SX, SY, n, c.solar, 2, 200, true)
    for i = 1, n do P:dot(SX[i], SY[i], 2, c.solar, 210) end

    -- 日均线
    o.barAvg = sum / n
    local ya = p.y + p.h - fx.clamp(o.barAvg / vmax, 0, 1) * p.h
    P:dash(p.x, ya, p.x + p.w, ya, c.txt, 1, 55, 5, 5)
end

local function draw_chart()
    local P = o.pChart
    local p = T.plot
    P:reset()

    -- 日/周/月 胶囊
    for i = 1, 3 do
        local x = 234 + (i - 1) * 46
        if i == o.view then
            P:box(x, 8, 44, 22, c.home, 42, 11)
            P:frame(x, 8, 44, 22, c.home, 1, 210, 11)
        else
            P:frame(x, 8, 44, 22, c.line2, 1, 120, 11)
        end
    end

    -- 图例色点
    P:dot(20, 49, 4, c.home, 235)
    P:dot(98, 49, 4, c.solar, 235)

    -- 网格
    for i = 0, 3 do
        local y = p.y + p.h * i / 3
        P:line(p.x, y, p.x + p.w, y, c.line2, 1, (i == 3) and 100 or 40)
    end
    for i = 0, 4 do
        local x = p.x + p.w * i / 4
        P:line(x, p.y, x, p.y + p.h, c.line2, 1, 40)
    end

    if o.view == 1 then draw_day(P, p) else draw_bars(P, p) end
    o.chartShape:set_items(P:finish())
end

-- ==================== 绘制：分路卡 ====================
local function draw_circ()
    local P = o.pCirc
    local row = T.circ_row
    P:reset()

    -- 按当前功率从大到小排：谁最费电就排最上面
    local idx = {}
    for i = 1, data.NCIRC do idx[i] = i end
    table.sort(idx, function(a, b)
        return (data.circuits[a].now or 0) > (data.circuits[b].now or 0)
    end)
    o.rowMap = idx

    local mx = 0.2
    for i = 1, data.NCIRC do
        local v = data.circuits[i].now or 0
        if v > mx then mx = v end
    end

    for r = 1, data.NCIRC do
        local cc = data.circuits[idx[r]]
        local y = row.y + (r - 1) * (row.h + row.gap)
        if o.pressRow == r then
            P:box(6, y - 2, 252, row.h - 2, cc.color, 22, 6)
        end
        if r < data.NCIRC then
            P:line(12, y + row.h + 1, 252, y + row.h + 1, c.line, 1, 70)
        end
        local kw = cc.now or 0
        local col = cc.on and cc.color or c.line2
        P:box(12, y + 19, 176, 4, 0x142232, 255, 2)
        if kw > 0.01 then
            local w = math.max(3, math.floor(176 * kw / mx))
            P:box(12, y + 19, w, 4, col, 225, 2)
            P:dot(12 + w, y + 21, 3, col, 90)
        end
    end
    o.circShape:set_items(P:finish())
end

-- ==================== 量程计算 ====================
--[[Y 轴量程取 3 的整数倍（周/月取 5 的整数倍）
为什么不用"当前最大值"直接当量程：曲线贴顶会压掉呼吸空间，
而量程每帧微调会让整张图的网格跟着上下抖，观感很差。]]
local function calc_max()
    local m = 0
    for i = 1, data.NPT do
        local a, b = data.day.load[i] or 0, data.day.pv[i] or 0
        if a > m then m = a end
        if b > m then m = b end
    end
    o.dayMax = math.max(3, math.ceil(m / 3) * 3)

    local d = (o.view == 2) and data.week or data.month
    local bm = 0
    for i = 1, d.n do
        local a, b = d.load[i] or 0, d.pv[i] or 0
        if a > bm then bm = a end
        if b > bm then bm = b end
    end
    o.barMax = math.max(5, math.ceil(bm / 5) * 5)
end

-- ==================== 文字刷新 ====================
local WD = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }
local HINT_DEFAULT = "触摸分路行可开关电器，触摸储能节点切换策略，触摸曲线卡切换日/周/月"

local function update_axis()
    local vmax = (o.view == 1) and (o.dayMax or 6) or (o.barMax or 10)
    for i = 0, 3 do
        -- v 是浮点（vmax * (1 - i/3)），直接给 "%d" 会因"数字无整数表示"抛错，
        -- 例如 vmax=18 时 i=1 得 12.000000000000002，Lua 5.3 拒绝转换
        local v = vmax * (1 - i / 3)
        kit.put(o.yAxis[i + 1],
            (v >= 10) and i0(v) or string.format("%.1f", v), o, "y" .. i)
    end
    if o.view == 1 then
        for i = 1, 5 do kit.put(o.xAxis[i], tostring(T.axis[i]), o, "x" .. i) end
    else
        kit.put(o.xAxis[1], (o.view == 2) and "6天前" or "30天前", o, "x1")
        kit.put(o.xAxis[2], "", o, "x2")
        kit.put(o.xAxis[3], "", o, "x3")
        kit.put(o.xAxis[4], "", o, "x4")
        kit.put(o.xAxis[5], "今天", o, "x5")
    end
end

local function update_chart_texts()
    local td = data.today
    if o.view == 1 then
        local pk, ph = 0, 0
        for i = 1, data.NPT do
            if (data.day.load[i] or 0) > pk then
                pk = data.day.load[i]
                ph = (i - 1) * 24 / data.NPT
            end
        end
        kit.put(o.lbFootL, string.format("峰值 %.1fkW  %02d:%02d",
            pk, math.floor(ph), math.floor((ph % 1) * 60)), o, "fl")
        kit.put(o.lbFootR, string.format("今日用电 %.1f kWh", td.load), o, "fr")
        kit.put(o.lbPeak, string.format("当前 %.2f kW", data.state.load), o, "pk")
    else
        local d = (o.view == 2) and data.week or data.month
        local sum, pvsum = 0, 0
        for i = 1, d.n do
            sum = sum + d.load[i]
            pvsum = pvsum + d.pv[i]
        end
        local label = (o.view == 2) and "本周" or "本月"
        kit.put(o.lbFootL, string.format("%s %.1f kWh", label, sum), o, "fl")
        kit.put(o.lbFootR, string.format("日均 %.1f kWh", sum / d.n), o, "fr")
        kit.put(o.lbPeak, string.format("发电 %.1f kWh", pvsum), o, "pk")
    end
end

local function update_texts()
    local s, td = data.state, data.today

    kit.put(o.lbClock, data.clock_str(), o, "clock")
    local lt = os.date("*t")
    kit.put(o.lbDate, string.format("%d月%d日 %s", lt.month, lt.day, WD[lt.wday] or ""), o, "date")
    kit.put(o.lbPrice, string.format("%s段 %.2f", s.seg or "平", s.price or 0.56), o, "price")
    kit.put(o.lbGrid, (s.grid < -0.05) and "售电中" or "并网", o, "gridmode")

    -- 顶栏三个设备状态
    kit.put(o.st[1], (s.pv > 0.05) and ("发电 " .. f2(s.pv) .. "kW") or "夜间待机", o, "st1")
    kit.tint(o.st[1], (s.pv > 0.05) and c.solar or c.dim2, o, "st1c")
    kit.put(o.st[2], (s.grid > 0.05) and ("购电 " .. f2(s.grid) .. "kW")
        or ((s.grid < -0.05) and ("售电 " .. f2(-s.grid) .. "kW") or "功率平衡"), o, "st2")
    kit.tint(o.st[2], c.grid, o, "st2c")
    kit.put(o.st[3], (s.bat > 0.05) and ("充电 " .. f2(s.bat) .. "kW")
        or ((s.bat < -0.05) and ("放电 " .. f2(-s.bat) .. "kW") or "待机"), o, "st3")
    kit.tint(o.st[3], c.batt, o, "st3c")

    -- KPI 四块
    local k = o.kpi
    kit.put(k[1].lbVal, f2(s.load), o, "k1v")
    kit.put(k[1].lbSub, string.format("今日 %.1f kWh", td.load), o, "k1s")
    kit.put(k[2].lbVal, f2(s.pv), o, "k2v")
    kit.put(k[2].lbSub, string.format("今日 %.1f kWh", td.pv), o, "k2s")
    kit.put(k[3].lbVal, f2(math.abs(s.grid)), o, "k3v")
    kit.put(k[3].lbUnit, (s.grid < -0.05) and "kW 售" or "kW 购", o, "k3u")
    kit.put(k[3].lbSub, string.format("今日购电 %.1f kWh", td.buy), o, "k3s")
    kit.put(k[4].lbVal, i0(s.soc), o, "k4v")
    kit.put(k[4].lbSub, string.format("容量 %.0fkWh  %s", data.cfg.bat_kwh,
        data.BAT_MODE[s.bat_mode].name), o, "k4s")

    -- 流向卡四个节点
    local fv = o.fv
    kit.put(fv.pvVal, f2(s.pv) .. "kW", o, "fpv")
    kit.tint(fv.pvVal, (s.pv > 0.05) and c.solar or c.dim2, o, "fpvc")
    kit.put(fv.btVal, ((s.bat >= 0) and "+" or "-") .. f2(math.abs(s.bat)) .. "kW", o, "fbt")
    kit.put(fv.btMode, data.BAT_MODE[s.bat_mode].name, o, "fbm")
    kit.put(fv.gdVal, ((s.grid >= 0) and "" or "-") .. f2(math.abs(s.grid)) .. "kW", o, "fgd")
    kit.tint(fv.gdVal, (s.grid >= 0) and c.buy or c.ok, o, "fgdc")
    kit.put(fv.hmVal, f2(s.load), o, "fhm")
    local rate = data.self_rate()
    kit.put(fv.ftVal, i0(rate * 100) .. "%", o, "frate")
    kit.tint(fv.ftVal, kit.level(1 - rate), o, "fratec")
    kit.put(o.flowTag, (s.pv > 0.05) and "实时" or "夜间", o, "ftag")

    -- 分路排行
    for r = 1, data.NCIRC do
        local ci = o.rowMap[r] or r
        local cc = data.circuits[ci]
        local row = o.rows[r]
        kit.put(row.name, cc.name, o, "rn" .. r)
        kit.put(row.val, f2(cc.now or 0) .. "kW", o, "rv" .. r)
        kit.tint(row.name, cc.on and c.dim or c.dim2, o, "rnc" .. r)
        kit.tint(row.val, cc.on and cc.color or c.dim2, o, "rvc" .. r)
    end

    -- 底部汇总
    kit.put(o.stats[1].val, f1(td.load), o, "s1")
    kit.put(o.stats[2].val, f1(td.pv), o, "s2")
    kit.put(o.stats[3].val, i0(rate * 100) .. "%", o, "s3")
    kit.put(o.stats[4].val, f1(data.net_cost()), o, "s4")
    kit.put(o.stats[5].val, f1(td.co2), o, "s5")
end

-- ==================== 视图切换 ====================
local function set_view(v)
    if o.view == v then return end
    o.view = v
    for i = 1, 3 do
        kit.tint(o.segLb[i], (i == v) and c.txt or c.dim, o, "seg" .. i)
    end
    calc_max()
    update_axis()
    update_chart_texts()
    draw_chart()
end

-- ==================== 提示行播报 ====================
-- 不弹浮层：这块屏是"常亮的信息面板"，弹窗遮住数据反而碍事，
-- 所以所有反馈都写在底部提示行，4 秒后自动回落到默认操作提示。
function M.say(msg)
    o.hintT = 4
    kit.put(o.lbHint, msg, o, "hint")
end

--[[一句话两种说法
屏上那条提示行是"读"的：空间只有一行、看的人也知道 kW/kWh，缩写反而信息密度高；
语音是"听"的：没有回看机会，术语必须先翻译成大白话再说数字。
所以凡是"既上屏又出声"的动作都走这里，两个文案写在一起，改的时候不会漏掉一边。
@param string ui     提示行文案（缩写版）
@param string speech 语音文案（口语版），省略时与 ui 相同
]]
local function tell(ui, speech)
    M.say(ui)
    voice.say(speech or ui)
end

-- ==================== 触摸 ====================
function M.on_touch(state, x, y)
    if not o.root then return end
    if type(x) ~= "number" or type(y) ~= "number" then return end
    if state ~= TP_DOWN then return end
    o.idle = 0

    -- 右下角语音开关：先关声音再提示，静音时这一句本来也就不会念出来
    if hit(x, y, 700, 550, 312, 40) then
        if not voice.ready() then
            M.say((rtos and rtos.bsp and rtos.bsp() == "PC")
                and "PC 模拟器没有音频输出，语音请在真机上验证"
                or "当前固件没有语音能力（缺 TTS 库）")
            return
        end
        local on = voice.toggle()
        draw_voice_btn()
        if on then voice.say("语音已开启") end
        M.say(on and "语音播报已开启" or "语音播报已静音，点击可恢复")
        return
    end

    -- 曲线卡：日 / 周 / 月
    for i = 1, 3 do
        if hit(x, y, T.chart.x + 234 + (i - 1) * 46, T.chart.y + 8, 44, 22) then
            set_view(i)
            tell("统计粒度：" .. SEG[i], "曲线改成看" .. SEG_SAY[i])
            return
        end
    end

    -- 分路卡：点哪行开关哪路
    local rr, row = T.circ, T.circ_row
    local listH = data.NCIRC * (row.h + row.gap)
    if hit(x, y, rr.x, rr.y + row.y, rr.w, listH) then
        local r = math.floor((y - rr.y - row.y) / (row.h + row.gap)) + 1
        local ci = o.rowMap and o.rowMap[r]
        if ci then
            local on = data.toggle_circuit(ci)
            local cc = data.circuits[ci]
            -- 闪一下高亮：重画一次带高亮的排行，下一次定时重画自然把它抹掉
            o.pressRow = r
            draw_circ()
            o.pressRow = nil
            tell(cc.name .. (on and " 已开启" or " 已关闭") .. "，曲线与排行已重算",
                cc.name .. (on and "已打开" or "已关掉"))
            update_texts()
            update_chart_texts()
            draw_flow()
            draw_kpi()
            return
        end
    end

    -- 流向卡：四个节点
    local fr, n = T.flow, T.node
    local function inNode(nd, pad)
        local dx = x - (fr.x + nd.x)
        local dy = y - (fr.y + nd.y)
        local r = nd.r + (pad or 10)
        return dx * dx + dy * dy <= r * r
    end
    -- 四个节点的详情：屏上一行缩写，语音一句大白话（见 tell 的注释）
    local msg, say
    if inNode(n.batt) then
        local m = data.cycle_bat_mode()
        local bm = data.BAT_MODE[m]
        msg = "储能策略：" .. bm.name .. "（再点一次切换下一种）"
        -- 策略名本身是行业词，光念"峰谷套利"等于没说话，必须补一句解释
        say = "储能现在是" .. bm.name .. "，" .. (bm.say or "")
        update_texts()
        draw_flow()
    elseif inNode(n.pv) then
        msg = string.format("光伏 %.2fkW  今日 %.1fkWh  装机 %.1fkWp",
            data.state.pv, data.today.pv, data.cfg.pv_kwp)
        -- "装机 kWp"在耳朵里等于乱码：说成"光伏板总容量"，单位只说千瓦
        say = string.format("光伏现在发 %.2f 千瓦，今天一共发了 %.1f 千瓦时，光伏板总容量 %.1f 千瓦",
            data.state.pv, data.today.pv, data.cfg.pv_kwp)
    elseif inNode(n.grid) then
        local s = data.state
        msg = string.format("电网 %.2fkW  %s段 %.2f元/度  今日购电 %.1fkWh",
            math.abs(s.grid), s.seg, s.price, data.today.buy)
        -- 同一个数字，买电和卖电在耳朵里是两件事，必须先把方向说出来
        local buying = s.grid >= -0.05
        say = string.format(buying
            and "现在从电网取 %.2f 千瓦，电价%s，一度 %.2f 元，今天买电 %.1f 千瓦时"
            or  "现在往电网送 %.2f 千瓦，电价%s，一度 %.2f 元，今天卖电 %.1f 千瓦时",
            math.abs(s.grid), SEG_NAME[s.seg] or "平时段", s.price,
            buying and data.today.buy or data.today.sell)
    elseif inNode(n.home) then
        msg = string.format("家庭负载 %.2fkW  在用分路 %d/%d  今日已用 %.1fkWh",
            data.state.load, data.total_on(), data.NCIRC, data.today.load)
        -- "家庭负载""分路"是配电箱上的词，家里人说"用电""电器"
        say = string.format("家里现在用电 %.2f 千瓦，%d 个电器里开着 %d 个，今天一共用了 %.1f 千瓦时",
            data.state.load, data.NCIRC, data.total_on(), data.today.load)
    end
    if msg then tell(msg, say) end
end

--[[状态拐点播报：提示行 + 语音各来一遍
不用定时播报（每 5 分钟念一次电量那种），只在"状态真的变了"时说一句，
语音侧还有最小间隔与同句去抖兜底，仿真时间快进时不会连珠炮。]]
local function announce(msg, say)
    M.say(msg)
    voice.auto(say or msg)
end

-- ==================== 每帧推进 ====================
function M.update(dt)
    o.anim = o.anim + dt
    o.idle = o.idle + dt

    -- 语音后端在独立任务里异步探测：就绪状态一变就重画右下角那个小图标
    if o.voiceReady ~= voice.ready() then
        o.voiceReady = voice.ready()
        draw_voice_btn()
    end

    -- 电价换段 / 售电状态翻转：边沿检测，一天只在几个时刻说话
    local seg = data.state.seg
    if seg ~= o.segLast then
        o.segLast = seg
        if seg == "谷" then
            announce(string.format("已进入谷段电价，电价 %.2f 元，适合给储能充电", data.state.price),
                string.format("现在是低谷电价，一度 %.2f 元，这个时段电最便宜，正在给电池充电",
                    data.state.price))
        elseif seg == "峰" then
            announce(string.format("已进入峰段电价，电价 %.2f 元，储能优先放电", data.state.price),
                string.format("现在到高峰电价了，一度 %.2f 元，电池开始放电，尽量少买电网的电",
                    data.state.price))
        end
    end
    local selling = data.state.grid < -0.05
    if selling ~= o.sellLast then
        o.sellLast = selling
        announce(selling and "光伏余电开始上网卖电" or "余电上网结束，转为电网供电",
            selling and "光伏发的电用不完了，多余的开始卖给电网"
                    or "光伏发的电不够用了，现在改从电网买电")
    end

    -- 展厅模式：12 秒没人碰，曲线自动轮播日 / 周 / 月
    if o.idle > T.perf.auto_chart_sec then
        o.idle = 0
        set_view(o.view % 3 + 1)
    end

    -- 提示行回落到默认文案
    if o.hintT and o.hintT > 0 then
        o.hintT = o.hintT - dt
        if o.hintT <= 0 then kit.put(o.lbHint, HINT_DEFAULT, o, "hint") end
    end

    -- 文字 4Hz
    o.tText = (o.tText or 0) + dt
    if o.tText >= 0.25 then
        o.tText = 0
        calc_max()
        update_texts()
        update_axis()
        update_chart_texts()
        draw_chips()
        draw_kpi()
    end

    -- 流向图 15fps（光点在跑，是唯一"每帧都在变"的图层）
    o.tFlow = (o.tFlow or 0) + dt
    if o.tFlow >= T.perf.flow_ms / 1000 then
        o.tFlow = 0
        draw_flow()
    end

    -- 分路条 2Hz
    o.tCirc = (o.tCirc or 0) + dt
    if o.tCirc >= T.perf.circ_ms / 1000 then
        o.tCirc = 0
        draw_circ()
    end

    -- 曲线 1Hz
    o.tChart = (o.tChart or 0) + dt
    if o.tChart >= T.perf.chart_ms / 1000 then
        o.tChart = 0
        draw_chart()
    end
end

-- ==================== 构建入口 ====================
function M.build()
    o.view = 1
    o.anim = 0
    o.idle = 0
    o.pressRow = nil
    -- 拐点播报的基准值：不清空的话开机第一帧会误报一次"状态变化"
    o.segLast = data.state.seg
    o.sellLast = data.state.grid < -0.05
    o.voiceReady = voice.ready()

    build_bg()
    build_top()
    build_kpi()
    build_flow()
    build_chart()
    build_circ()
    build_stats()
    build_hint()

    -- 首帧一次性把所有动态层画满，避免开机看到空画布
    calc_max()
    update_texts()
    update_axis()
    update_chart_texts()
    draw_flow()
    draw_kpi()
    draw_chips()
    draw_chart()
    draw_circ()
    draw_voice_btn()

    airui.touch_subscribe(function(state, x, y)
        M.on_touch(state, x, y)
    end)
    log.info("energy", "面板构建完成")
end

return M
