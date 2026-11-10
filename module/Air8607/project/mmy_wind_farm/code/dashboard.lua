--[[
@module  dashboard
@summary 北岭风电场 - 主界面（功率曲线 / 机组阵列 / 风向玫瑰 / 事件流 / KPI）
@version 1.0
@date    2026.11.09
@board   Air8607 + 1024x600 RGB 屏 + GT911 触摸

=== 这块屏要回答四个问题 ===
1、现在发多少、装机用了多少            -> KPI 第一块 + 功率曲线
2、哪几台没在转、为什么没在转          -> 机组阵列（转子停转 + 砖块染色）
3、风从哪来、这个场站的风什么时候来    -> 风向玫瑰（瓣长 = 出现频率，瓣色 = 风速）
4、刚才发生了什么、还有谁没确认        -> 事件流（最新 4 条，点一下确认）

=== 图层与重绘节奏 ===
静态层（开机画一次）：背景色带、顶栏分隔线、卡片底、标题文字、机组编号
动态层（分区重绘，互不牵连）：
  机组阵列  120ms  转子转角 + 出力刻度 + 状态点（唯一的高频区）
  事件流    500ms  新事件插入后重排前 4 条
  玫瑰/曲线 1s     风向分布、今日功率
  文字      250ms  节流，避免每帧几十次 set_text 触发 LVGL 重排

=== 触摸热区（1024x600 绝对坐标）===
  机组砖块  第一次点 = 选中（底部详情跟随）；再点同一块 = 检修挂牌 / 复位并网
  AGC 胶囊  点一次 = 模拟调度下发限电，再点解除（演示现场调峰最直观）
  事件行    点任意一条 = 确认该条；卡头"全部确认"一次清掉
  12 秒无人操作后自动轮播选中机组（中控室看板模式）
]]

local T = require "theme"
local fx = require "fx"
local kit = require "kit"
local data = require "wind_data"
local voice = require "voice"

local M = {}
local c, f = T.c, T.f
local o = {}
local TILE = T.tile          -- 机组砖块尺寸，绘制和触摸判定两处都要用，取同一个源

-- airui 的触摸状态枚举；个别固件没导出这个常量，下面用时间去抖兜底
local TP_DOWN = airui.TP_DOWN
local L, CE, R = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT

local function f1(v) return string.format("%.1f", v) end
local function f2(v) return string.format("%.2f", v) end
local function i0(v) return string.format("%d", math.floor(v + 0.5)) end

local function hit(x, y, rx, ry, rw, rh)
    return x >= rx and x < rx + rw and y >= ry and y < ry + rh
end

-- 机组状态 -> 颜色
local function tcolor(st)
    if st == 2 then return c.alarm end
    if st == 3 then return c.amber end
    if st == 1 then return c.dim2 end
    return c.wind
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
        P:box(0, i * 50, T.screen.w, 51, fx.mix(0x0A1A1C, 0x03080A, i / 11), 255)
    end
    P:line(0, 56, T.screen.w, 56, c.line, 1, 180)

    -- 底部汇总条每格顶上的彩条
    local cols = { c.wind, c.fcst, c.amber, c.ok, c.aurora }
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
    -- AGC 胶囊要随限电状态变色，单独一张小画布
    o.chipShape = airui.shape({ parent = o.root, x = 812, y = 4, w = 204, h = 46 })
    o.pChip = fx.pool()

    kit.text(o.root, 20, 8, 240, 26, 20, c.txt, L, "北岭风电场")
    kit.text(o.root, 20, 35, 240, 14, f.mini, c.dim2, L, "NORTH RIDGE WIND FARM")

    o.st = {}
    local xs = { 268, 390, 512 }
    local names = { "并网状态", "在线机组", "调度指令" }
    for i = 1, 3 do
        kit.text(o.root, xs[i], 11, 112, 14, f.mini, c.dim, L, names[i])
        o.st[i] = kit.text(o.root, xs[i], 29, 112, 17, f.body, c.txt, L, "--")
    end

    o.lbClock = kit.text(o.root, 628, 6, 150, 32, 26, c.txt, L, "09:00")
    o.lbDate = kit.text(o.root, 628, 37, 150, 14, f.mini, c.dim2, L, "--")

    o.lbMode = kit.text(o.root, 820, 10, 188, 20, f.sub, c.txt, CE, "AGC 自由发电")
    o.lbSync = kit.text(o.root, 820, 32, 188, 14, f.mini, c.dim2, CE, "点此模拟限电")
end

-- ==================== KPI 四块 ====================
local KPI = {
    { name = "实时功率",   color = c.wind,   unit = "MW" },
    { name = "平均风速",   color = c.aurora, unit = "m/s" },
    { name = "今日发电",   color = c.fcst,   unit = "MWh" },
    { name = "机组可用率", color = c.ok,     unit = "%" },
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
            lbVal = kit.text(card, 13, 24, 136, 34, f.hero, KPI[i].color, L, "0"),
            lbUnit = kit.text(card, 152, 40, 54, 16, f.mini, c.dim2, L, KPI[i].unit),
            lbSub = kit.text(card, 14, 58, 218, 14, f.mini, c.dim2, L, ""),
        }
        kit.text(card, 14, 9, 170, 15, f.mini, c.dim, L, KPI[i].name)
    end
end

-- ==================== 功率曲线卡 ====================
local function build_curve()
    local r, p = T.curve, T.plot
    local card = kit.card(o.root, r, c.wind)
    o.curveShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pCurve = fx.pool()
    kit.head(card, "全场有功 今日", 170)
    kit.tag(card, 168, 12, 160, "15 分钟一格  共 96 点", c.dim2)

    o.lbLegend1 = kit.text(card, 34, 50, 58, 16, f.mini, c.dim, L, "实测")
    o.lbLegend2 = kit.text(card, 142, 50, 58, 16, f.mini, c.dim, L, "预测")
    o.lbNow = kit.text(card, 186, 50, 144, 16, f.mini, c.txt, R, "")

    o.yAxis = {}
    for i = 1, 4 do
        o.yAxis[i] = kit.text(card, 0, p.y + p.h * (i - 1) / 3 - 7, p.x - 8, 14, f.mini, c.dim2, R, "")
    end
    o.xAxis = {}
    for i = 1, 5 do
        local x = p.x + p.w * (i - 1) / 4
        o.xAxis[i] = kit.text(card, x - 16, p.y + p.h + 4, 32, 14, f.mini, c.dim2, CE, "")
    end

    o.lbFootL = kit.text(card, p.x, 274, 170, 16, f.mini, c.dim, L, "")
    o.lbFootR = kit.text(card, 186, 274, 144, 16, f.mini, c.dim2, R, "")
end

-- ==================== 机组阵列 ====================
local function build_farm()
    local r, t = T.farm, T.tile
    local card = kit.card(o.root, r, c.wind)
    o.farmShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pFarm = fx.pool()
    o.farmCard = card
    kit.head(card, "机组阵列", 110)
    kit.tag(card, 160, 12, 168, "点选 / 再点挂牌", c.dim2)

    o.tiles = {}
    for i = 1, data.N do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = t.x + col * (t.w + t.gapx)
        local y = t.y + row * (t.h + t.gapy)
        o.tiles[i] = {
            x = x, y = y,
            name = kit.text(card, x + 7, y + 3, 46, 13, f.mini, c.dim, L, data.turbines[i].short),
            power = kit.text(card, x + 7, y + 51, 50, 17, f.val, c.wind, L, ""),
            unit = kit.text(card, x + 52, y + 55, 26, 13, f.mini, c.dim2, L, "MW"),
        }
    end

    -- 卡片底部一行：选中机组的完整读数（比弹窗轻，不遮数据）
    o.lbFarmFoot = kit.text(card, 12, 294, r.w - 24, 16, f.mini, c.dim, L, "")
end

-- ==================== 风向玫瑰 ====================
local RC = T.roseC

local function build_rose()
    local r = T.rose
    local card = kit.card(o.root, r, c.aurora)
    o.roseShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pRose = fx.pool()
    kit.head(card, "风向玫瑰", 130)
    kit.tag(card, 130, 12, 116, "瓣长 = 频率", c.dim2)

    o.lbRoseVal = kit.text(card, RC.cx - 30, RC.cy - 12, 60, 20, f.body, c.txt, CE, "")
    o.lbRoseUnit = kit.text(card, RC.cx - 30, RC.cy + 8, 60, 13, f.mini, c.dim2, CE, "m/s")

    -- 罗盘四向只标 N/E/S/W：hzfont 没有度数符号，方位字比箭头更省宽度
    kit.text(card, RC.cx - 6, RC.cy - RC.r - 13, 20, 13, f.mini, c.dim2, CE, "N")
    kit.text(card, RC.cx + RC.r - 3, RC.cy - 7, 20, 13, f.mini, c.dim2, CE, "E")
    kit.text(card, RC.cx - 6, RC.cy + RC.r - 3, 20, 13, f.mini, c.dim2, CE, "S")
    kit.text(card, RC.cx - RC.r - 19, RC.cy - 7, 20, 13, f.mini, c.dim2, CE, "W")

    o.lbRoseL1 = kit.text(card, 132, 44, 112, 13, f.mini, c.dim2, L, "主导风向")
    o.lbRoseV1 = kit.text(card, 132, 58, 112, 20, f.body, c.aurora, L, "")
    o.lbRoseL2 = kit.text(card, 132, 84, 112, 13, f.mini, c.dim2, L, "当前风向")
    o.lbRoseV2 = kit.text(card, 132, 98, 112, 20, f.body, c.txt, L, "")
    o.lbRoseL3 = kit.text(card, 132, 122, 112, 13, f.mini, c.dim2, L, "")
end

-- ==================== 事件流 ====================
local NEVENT_ROW = 4

local function build_event()
    local r, er = T.event, T.event_row
    local card = kit.card(o.root, r, c.alarm)
    o.eventShape = airui.shape({ parent = card, x = 0, y = 0, w = r.w, h = r.h })
    o.pEvent = fx.pool()
    o.eventCard = card
    kit.head(card, "运行事件", 110)
    o.lbAck = kit.text(card, 132, 11, 114, 18, f.mini, c.dim2, R, "全部确认")

    o.evRows = {}
    for i = 1, NEVENT_ROW do
        local y = er.y + (i - 1) * (er.h + er.gap)
        o.evRows[i] = {
            y = y,
            time = kit.text(card, er.x + 13, y + 1, 46, 13, f.mini, c.dim2, L, ""),
            text = kit.text(card, er.x + 13, y + 12, er.w - 20, 15, f.sub, c.txt, L, ""),
        }
    end
    o.lbEvEmpty = kit.text(card, 12, 70, 232, 16, f.sub, c.dim2, CE, "暂无事件")
end

-- ==================== 底部汇总 ====================
local STAT = {
    { name = "今日发电量", color = c.wind,   unit = "MWh  装机 75MW" },
    { name = "容量系数",   color = c.fcst,   unit = "%  实际/理论" },
    { name = "限电损失",   color = c.amber,  unit = "MWh  折算电量" },
    { name = "CO2 减排",   color = c.ok,     unit = "吨  相对火电" },
    { name = "今日收益",   color = c.aurora, unit = "万元  电价 0.42" },
}

local function build_stats()
    o.stats = {}
    for i = 1, 5 do
        local x = T.stat.x + (i - 1) * (T.stat.w + T.stat.gap)
        local r = { x = x, y = T.stat.y, w = T.stat.w, h = T.stat.h }
        local card = kit.card(o.root, r, nil)
        o.stats[i] = {
            name = kit.text(card, 14, 10, 168, 15, f.mini, c.dim, L, STAT[i].name),
            val = kit.text(card, 14, 27, 124, 28, f.num, STAT[i].color, L, "0"),
            unit = kit.text(card, 14, 56, 170, 14, f.mini, c.dim2, L, STAT[i].unit),
        }
    end
end

local function build_hint()
    o.lbHint = kit.text(o.root, 14, 561, 560, 16, f.mini, c.dim2, L, "")
    o.lbSpeed = kit.text(o.root, 576, 561, 128, 16, f.mini, c.dim2, R, "演示 60x")

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
        local pc = false
        if rtos and rtos.bsp then
            local ok, bsp = pcall(rtos.bsp)
            pc = ok and bsp == "PC"
        end
        txt = pc and "PC 模拟器无语音（真机可用）" or "语音不可用（固件无 TTS）"
    elseif on then
        txt = "语音开  点此静音"
    else
        txt = "语音关  点此开启"
    end
    kit.put(o.lbVoice, txt, o, "voice")
    kit.tint(o.lbVoice, on and c.dim or c.dim2, o, "voicec")
end

-- ==================== 绘制：机组阵列（12 台，含转子动画）====================
--[[这是全屏唯一的高频区（120ms）
每块砖讲三件事：在不在转（转子）、出多少力（底部刻度 + 读数）、什么状态（砖块底色 + 右上点）
故障机不只变色，转子必须**停住**——中控室里"还在转但功率为 0"会被当成通信故障。
]]
local function draw_farm()
    local P = o.pFarm
    P:reset()
    local spin = o.spin or 0
    local tw, th = TILE.w, TILE.h

    for i = 1, data.N do
        local tb = data.turbines[i]
        local x, y = o.tiles[i].x, o.tiles[i].y
        local tc = tcolor(tb.status)
        local frac = (tb.cap > 0) and (tb.power / tb.cap) or 0

        -- 常亮屏纪律：正常机只留一点冷色底，异常机才整块染色
        local bgc = c.panel2
        if tb.status == 2 then
            bgc = fx.mix(c.panel2, c.alarm, 0.22)
        elseif tb.status == 3 then
            bgc = fx.mix(c.panel2, c.amber, 0.16)
        elseif tb.curt then
            bgc = fx.mix(c.panel2, c.amber, 0.09)
        end
        P:box(x, y, tw, th, bgc, 255, 5)
        P:frame(x, y, tw, th, (o.sel == i) and c.aurora or c.line, 1,
                (o.sel == i) and 210 or 110, 5)

        -- 转子：单机转速不同（14.8rpm 为满速），停机时角度不再推进
        local spin_k = (tb.rpm > 0.3) and (tb.rpm / 14.8) or 0
        local ang = tb.phase + spin * spin_k
        fx.rotor(P, x + tw / 2, y + 35, 15, ang, tc, 2, (tb.status == 2) and 235 or 200)

        -- 出力刻度：底部一条 3px 量条，一眼看出哪几台在满发
        -- 底槽色用 fx.meter 的默认值，砖块底色本来就是 panel2，差一档看不出来
        kit.meter(P, x + 8, y + 71, tw - 16, 3, frac, tc)

        -- 状态点
        P:dot(x + tw - 9, y + 9, 2.5, tc, 235)
    end

    -- 选中括号画在最后：压在砖块之上，且只画一次
    local st = o.tiles[o.sel]
    if st then
        kit.brackets(P, st.x - 2, st.y - 2, tw + 4, th + 4, c.aurora, 220, 9)
    end
    o.farmShape:set_items(P:finish())
end

-- ==================== 绘制：今日功率曲线 ====================
local VMAX = 80   -- 满量程固定 80MW（装机 75MW），不随数据缩放，刻度不会跳

local function draw_curve()
    local P = o.pCurve
    P:reset()
    local p = T.plot
    local x, y, w, h = p.x, p.y, p.w, p.h
    local idx = data.now_index()
    local meas, fcst = data.hist.meas, data.hist.fcst
    local step = w / (data.NPT - 1)

    -- 网格：横 4 根（含底轴）、竖 4 根
    for i = 0, 3 do
        local gy = y + h * i / 3
        P:line(x, gy, x + w, gy, c.line, 1, (i == 3) and 130 or 70)
    end
    for i = 0, 4 do
        local gx = x + w * i / 4
        P:line(gx, y, gx, y + h, c.line, 1, 45)
    end

    -- 装机容量参考线：让"离满发还有多远"变成一个可以直接看的距离
    local capy = y + h - (data.NCAP / VMAX) * h
    P:dash(x, capy, x + w, capy, c.line2, 1, 150, 5, 4)

    -- 预测：整条压在底层，低透明度虚线，只做"本该发多少"的对照
    local px_, py_ = x, y + h - fx.clamp((fcst[1] or 0) / VMAX, 0, 1) * h
    for i = 2, data.NPT do
        local nx = x + (i - 1) * step
        local ny = y + h - fx.clamp((fcst[i] or 0) / VMAX, 0, 1) * h
        if i % 3 == 1 then P:dash(px_, py_, nx, ny, c.fcst, 1, 85, 3, 5) end
        px_, py_ = nx, ny
    end

    -- 实测：先铺面积再看折线，面积用 26 的低透明度，屏幕不会糊成一片
    kit.area(P, meas, idx, x, y, w, h, VMAX, c.wind, 24, 4, 1)
    kit.line(P, meas, idx, x, y, w, h, VMAX, c.wind, 2, 245)

    -- 当前时刻：竖线 + 双圈光点（外圈当光晕）
    local cx = x + (idx - 1) * step
    local cv = fx.clamp((meas[idx] or 0) / VMAX, 0, 1)
    local cy = y + h - cv * h
    P:line(cx, y, cx, y + h, c.aurora, 1, 55)
    P:dot(cx, cy, 5, c.aurora, 55)
    P:dot(cx, cy, 2.5, c.aurora, 255)

    o.curveShape:set_items(P:finish())
end

-- ==================== 绘制：风向玫瑰 ====================
--[[画法
16 个方位各一"瓣"：从圆心伸出的辐条 + 末端一段圆弧帽，长度 = 该方位出现频率。
瓣的颜色由该方位的平均风速决定（灰 = 微风，青 = 有效风，琥珀 = 大风），
所以这块图同时回答"风从哪来"和"那个方向的风有多大"两个问题。
]]
local function draw_rose()
    local P = o.pRose
    P:reset()
    local cx, cy, r = RC.cx, RC.cy, RC.r

    for k = 1, 3 do P:arc(cx, cy, r * k / 3, 0, 359, c.line, 1, 95) end
    P:line(cx - r, cy, cx + r, cy, c.line, 1, 35)
    P:line(cx, cy - r, cx, cy + r, c.line, 1, 35)

    local freq, spd = data.rose.freq, data.rose.spd
    local mx = 0
    for i = 1, data.ROSE_N do
        if freq[i] > mx then mx = freq[i] end
    end

    local maxlen = r - 6
    for i = 1, data.ROSE_N do
        local rel = (mx > 0) and (freq[i] / mx) or 0
        local len = 7 + rel * (maxlen - 7)
        local col = fx.mix(0x1B4A47, kit.wind_color(spd[i] or 0), 0.3 + 0.7 * rel)
        fx.petal(P, cx, cy, (i - 1) * 22.5, len, col, 4, 55 + math.floor(rel * 175))
    end

    -- 当前风向：一根亮辐条压在所有瓣上，末端一个小箭头
    local _, cur = data.compass(data.state.dir)
    local a = math.rad(data.state.dir - 90)
    local len = 7 + ((freq[cur] or 0) / (mx > 0 and mx or 1)) * (maxlen - 7) + 3
    P:line(cx, cy, cx + math.cos(a) * len, cy + math.sin(a) * len, c.aurora, 2, 220, true)
    fx.arrow(P, cx + math.cos(a) * len, cy + math.sin(a) * len,
             data.state.dir + 90, 6, c.aurora, 1, 230)

    -- 中心留白，压住辐条根部，风速数字才有地方站
    P:dot(cx, cy, 15, c.panel, 255)
    P:ring(cx, cy, 15, c.line2, 1, 200)
    o.roseShape:set_items(P:finish())
end

-- ==================== 绘制：事件流 ====================
--[[把事件当成"带时间戳的窄条卡片"：左侧 2px 色条表示等级，
点过就变灰但不会消失（中控室需要事后回看，和弹窗式通知是两回事）。]]
local function draw_event()
    local P = o.pEvent
    P:reset()
    local er = T.event_row
    local any = false

    for i = 1, NEVENT_ROW do
        local e = data.events[i]
        local row = o.evRows[i]
        if e then
            any = true
            local col
            if e.level == 3 then col = c.alarm
            elseif e.level == 2 then col = c.amber
            elseif e.level == 1 then col = c.wind
            else col = c.line2 end
            P:box(er.x, row.y, er.w, er.h, c.panel2, 255, 4)
            P:box(er.x, row.y, 2, er.h, col, (e.level > 0) and 235 or 110, 1)
            if e.level >= 2 then
                -- 未确认的告警：整条描一道同色细边
                P:frame(er.x, row.y, er.w, er.h, col, 1, 90, 4)
            end
        end
    end
    o.eventShape:set_items(P:finish())
    -- airui 的 label 没有 set_hidden / set_visible（只有 container 有），
    -- 空态只能靠"清空文字"表达：有事件时写空串，label 不占视觉
    kit.put(o.lbEvEmpty, any and "" or "暂无事件", o, "evempty")
end

-- ==================== 绘制：AGC 胶囊 + KPI 量条 ====================
local function draw_chip()
    local P = o.pChip
    P:reset()
    local curt = data.state.curt
    local col = curt and c.amber or c.ok
    P:box(0, 0, 204, 46, fx.mix(c.panel, col, 0.12), 255, 10)
    P:frame(0, 0, 204, 46, col, 1, 150, 10)
    P:dot(12, 23, 3, col, 255)
    o.chipShape:set_items(P:finish())
end

local function draw_kpi()
    for i = 1, 4 do
        local k = o.kpi[i]
        local P = k.pool
        P:reset()
        local frac
        if i == 1 then
            frac = data.state.power / data.NCAP
        elseif i == 2 then
            frac = data.state.wind / 25
        elseif i == 3 then
            frac = data.today.mwh / math.max(1, data.NCAP * math.max(0.5, data.state.hour))
        else
            frac = data.state.avail / 100
        end
        kit.meter(P, 13, 74, 216, 4, frac, k.color)
        k.shape:set_items(P:finish())
    end
end

-- ==================== 文字刷新（4Hz，内容不变不写）====================
local HINTS = {
    "点机组砖块查看单机读数，再点一次挂牌检修",
    "AGC 胶囊可直接切换限电 / 自由发电，用于演示调度",
    "风向玫瑰的瓣长是该方位的累计出现频率",
    "12 秒无操作会自动轮播机组，适合大屏值守",
}

local function refresh_top()
    local s = data.state
    local curt = s.curt
    kit.put(o.lbClock, data.clock_str(), o, "clk")
    kit.put(o.lbDate, o.dateStr or "", o, "date")

    local run = (s.power > 0.5)
    local st1 = curt and "限电中" or (run and "运行中" or "待风")
    kit.put(o.st[1], st1, o, "st1")
    kit.tint(o.st[1], curt and c.amber or (run and c.ok or c.dim), o, "st1c")

    kit.put(o.st[2], string.format("%d/%d", s.online, data.N), o, "st2")
    kit.tint(o.st[2], (s.online == data.N) and c.txt or c.amber, o, "st2c")

    local st3 = curt and string.format("限电 %.0fMW", s.curtail_limit) or "自由发电"
    kit.put(o.st[3], st3, o, "st3")
    kit.tint(o.st[3], curt and c.amber or c.txt, o, "st3c")

    kit.put(o.lbMode, curt and string.format("AGC 限电 %.0fMW", s.curtail_limit) or "AGC 自由发电", o, "mode")
    kit.tint(o.lbMode, curt and c.amber or c.ok, o, "modec")
    kit.put(o.lbSync, curt and "点此解除限电" or "点此模拟限电", o, "sync")
end

local function refresh_kpi()
    local s, td = data.state, data.today
    local k1 = o.kpi[1]
    kit.put(k1.lbVal, f1(s.power), o, "k1v")
    kit.put(k1.lbSub, string.format("装机 %.0fMW  负载 %d%%", data.NCAP, i0(s.power / data.NCAP * 100)), o, "k1s")

    local k2 = o.kpi[2]
    kit.put(k2.lbVal, f1(s.wind), o, "k2v")
    local cm = data.compass(s.dir)
    kit.put(k2.lbSub, string.format("阵风 %.1f  主导 %s", s.wind * 1.16, cm), o, "k2s")

    local k3 = o.kpi[3]
    kit.put(k3.lbVal, f1(td.mwh), o, "k3v")
    kit.put(k3.lbSub, string.format("容量系数 %d%%  等效 %.1fh", i0(data.cf()), td.mwh / data.NCAP), o, "k3s")

    local k4 = o.kpi[4]
    kit.put(k4.lbVal, f1(s.avail), o, "k4v")
    kit.put(k4.lbSub, string.format("在线 %d  故障 %d  检修 %d",
        s.online, data.count_status(2), data.count_status(3)), o, "k4s")
end

local function refresh_curve()
    kit.put(o.lbNow, string.format("当前 %sMW", f1(data.state.power)), o, "now")
    local ticks = { i0(VMAX), i0(VMAX * 2 / 3), i0(VMAX / 3), "0" }
    for i = 1, 4 do kit.put(o.yAxis[i], ticks[i], o, "ya" .. i) end
    local xs = { "00", "06", "12", "18", "24" }
    for i = 1, 5 do kit.put(o.xAxis[i], xs[i], o, "xa" .. i) end
    kit.put(o.lbFootL, string.format("装机 %.0fMW  峰值 %.1fMW", data.NCAP, data.today.peak), o, "fl")
    kit.put(o.lbFootR, string.format("容量系数 %.1f%%", data.cf()), o, "fr")
end

-- 机组阵列的文字：12 台单机读数，只在数值真的变了才 set_text
local function refresh_tiles()
    for i = 1, data.N do
        local tb = data.turbines[i]
        local row = o.tiles[i]
        local txt
        if tb.status == 2 then
            txt = "故障"
        elseif tb.status == 3 then
            txt = "检修"
        elseif tb.status == 1 then
            txt = "待风"
        else
            txt = f2(tb.power)
        end
        kit.put(row.power, txt, o, "tp" .. i)
        kit.tint(row.power, tcolor(tb.status), o, "tpc" .. i)
        kit.tint(row.unit, (tb.status == 0) and c.dim2 or c.line2, o, "tpu" .. i)
    end

    local tb = data.turbines[o.sel]
    if tb then
        local st
        if tb.status == 2 then st = "故障停机"
        elseif tb.status == 3 then st = "检修挂牌"
        elseif tb.status == 1 then st = "风速不足待机"
        elseif tb.curt then st = "限电降容"
        else st = "并网发电" end
        kit.put(o.lbFarmFoot, string.format("%s  %s  %.1fm/s  %.1frpm  桨距 %.1f  齿轮 %.0fC  %s",
            tb.name, st, tb.weff, tb.rpm, tb.pitch, tb.temp, tb.curt and "限" or ""), o, "ff")
    end
end

local function refresh_rose()
    local s = data.state
    kit.put(o.lbRoseVal, f1(s.wind), o, "rv")
    local freq = data.rose.freq

    -- 主导风向：出现频率最高的那个方位
    local mi, mv = 1, -1
    local total = 0
    for i = 1, data.ROSE_N do
        total = total + freq[i]
        if freq[i] > mv then mv, mi = freq[i], i end
    end
    -- 方位名从 data.compass 取，避免这里再抄一份 16 方位表（抄错一个字母很难查）
    local dom = data.compass((mi - 1) * 22.5)
    local curName = data.compass(s.dir)

    kit.put(o.lbRoseV1, string.format("%s  %d%%", dom, i0(mv / math.max(0.001, total) * 100)), o, "r1")
    kit.put(o.lbRoseV2, string.format("%s  %d 方位", curName, i0(s.dir)), o, "r2")
    kit.put(o.lbRoseL3, string.format("阵风 %.1fm/s", s.wind * 1.16), o, "r3")
end

local function refresh_event()
    for i = 1, NEVENT_ROW do
        local e = data.events[i]
        local row = o.evRows[i]
        if e then
            local col
            if e.level == 3 then col = c.alarm
            elseif e.level == 2 then col = c.amber
            elseif e.level == 1 then col = c.txt
            else col = c.dim2 end
            kit.put(row.time, e.t, o, "et" .. i)
            kit.put(row.text, e.text, o, "ex" .. i)
            kit.tint(row.text, col, o, "exc" .. i)
        else
            kit.put(row.time, "", o, "et" .. i)
            kit.put(row.text, "", o, "ex" .. i)
        end
    end

    local unacked = data.active_alarms()
    kit.put(o.lbAck, (unacked > 0) and string.format("全部确认 (%d)", unacked) or "全部已确认", o, "ack")
    kit.tint(o.lbAck, (unacked > 0) and c.txt or c.dim2, o, "ackc")
end

local function refresh_stats()
    local td = data.today
    local vals = {
        f1(td.mwh),
        f1(data.cf()),
        f1(td.loss),
        f1(data.co2_ton()),
        f1(data.cost() / 10000),
    }
    for i = 1, 5 do kit.put(o.stats[i].val, vals[i], o, "sv" .. i) end
end

local function refresh_text()
    refresh_top()
    refresh_kpi()
    refresh_curve()
    refresh_tiles()
    refresh_rose()
    refresh_event()
    refresh_stats()
    kit.put(o.lbHint, HINTS[(o.hintIdx or 1)], o, "hint")
    kit.put(o.lbSpeed, string.format("演示 %dx", data.cfg.demo_speed or T.perf.demo_speed), o, "spd")
end

-- ==================== 触摸交互 ====================
function M.select(i)
    if i < 1 or i > data.N then return end
    o.sel = i
    o.autoSel = false
    o.idle = 0
    draw_farm()
    refresh_tiles()
end

--[[触摸入口（ui_main 已把坐标统一到 1024x600）]]
function M.on_touch(x, y)
    o.idle = 0

    -- AGC 胶囊
    if hit(x, y, 812, 4, 204, 46) then
        local on = not data.state.curt
        data.set_curtail(on, false)
        draw_chip()
        refresh_top()
        refresh_kpi()
        draw_curve()
        draw_farm()
        draw_kpi()
        if on then
            voice.say(string.format("已模拟调度限电，出力压至 %.0f 兆瓦", data.state.curtail_limit), 2)
        else
            voice.say("限电解除，全场恢复自由发电", 2)
        end
        return true
    end

    -- 机组砖块
    for i = 1, data.N do
        local t = o.tiles[i]
        if hit(x, y, T.farm.x + t.x, T.farm.y + t.y, TILE.w, TILE.h) then
            -- 自动轮播状态下的一次点击只是"锁定到手指下面这台"，不该顺手把机组停了
            if o.autoSel then
                o.autoSel = false
                M.select(i)
                return true
            end
            if o.sel == i then
                local r = data.toggle_turbine(i)
                draw_farm()
                refresh_tiles()
                draw_curve()
                draw_kpi()
                if r == "stop" then
                    voice.say(data.turbines[i].name .. " 检修挂牌停机", 2)
                elseif r == "start" then
                    voice.say(data.turbines[i].name .. " 恢复并网", 1)
                elseif r == "reset" then
                    voice.say(data.turbines[i].name .. " 人工复位成功", 1)
                end
            else
                M.select(i)
            end
            return true
        end
    end

    -- 事件行 + 全部确认
    local er = T.event_row
    for i = 1, NEVENT_ROW do
        local ry = T.event.y + o.evRows[i].y
        if data.events[i] and hit(x, y, T.event.x + er.x, ry, er.w, er.h) then
            if data.ack_event(i) then
                draw_event()
                refresh_event()
            end
            return true
        end
    end
    if hit(x, y, T.event.x + 126, T.event.y + 4, 122, 26) then
        local n = data.ack_all()
        if n > 0 then
            draw_event()
            refresh_event()
        end
        return true
    end

    -- 语音开关（图标 + 右边文字整块可点）
    if hit(x, y, 706, 556, 300, 30) then
        local on = voice.toggle()
        draw_voice_btn()
        if on then voice.say("语音已开启", 1) end
        return true
    end

    return false
end

-- ==================== 构建与生命周期 ====================
function M.build()
    -- data.init() 由 ui_main.build 统一调用，这里不再重复初始化（否则会重建一次
    -- 机组表和 96 点曲线，日志里也会出现两遍"系统启动"）
    local d = os.date("*t")
    o.dateStr = string.format("%04d-%02d-%02d", d.year, d.month, d.day)
    o.sel = 1
    o.spin = 0
    o.idle = 0
    o.autoSel = false
    o.hintIdx = 1
    o.af, o.ac, o.ae, o.at = 1e9, 1e9, 1e9, 1e9

    build_bg()
    build_top()
    build_kpi()
    build_curve()
    build_farm()
    build_rose()
    build_event()
    build_stats()
    build_hint()

    draw_voice_btn()
    draw_chip()
    draw_farm()
    draw_curve()
    draw_rose()
    draw_event()
    draw_kpi()
    refresh_text()

    --[[触摸只认按下：UP 事件的坐标可能已经滑到隔壁砖块上，抬手误触比漏触更讨厌。
    回调跑在 LVGL 输入线程里，这里只做纯 Lua 的坐标判定 + 改数据 + 标脏，
    不创建/销毁任何控件 —— 跨线程重建对象是这块屏最容易崩的一种写法。]]
    if TP_DOWN == nil then
        log.warn("wind", "固件未导出 TP_DOWN，面板按只读模式运行")
    elseif airui.touch_subscribe then
        local ok = airui.touch_subscribe(function(state, x, y)
            if state ~= TP_DOWN then return end
            M.on_touch(x, y)
        end)
        if not ok then log.error("wind", "touch_subscribe 失败，屏幕不可点") end
    else
        log.warn("wind", "固件无 airui.touch_subscribe，面板只读")
    end

    log.info("wind", "面板构建完成", T.screen.w, T.screen.h)
end

--[[主循环：dt 为真实秒（由 ui_main 提供）
先推进数据，再按分区节拍重绘。所有节拍都用累加 + 归零，不用取模，
否则 dt 抖动时会漏帧或连帧。]]
function M.update(dt)
    data.tick(dt, T.perf.demo_speed)

    -- 转子角度：真实时间推进，和仿真倍率无关。满速 14.8rpm 约 84 度/秒，
    -- 120ms 一帧走 10 度，看起来是匀速转动而不是跳格
    o.spin = (o.spin or 0) + dt * 1.47

    local ms = dt * 1000
    o.af = (o.af or 0) + ms
    o.ac = (o.ac or 0) + ms
    o.ae = (o.ae or 0) + ms
    o.at = (o.at or 0) + ms

    if o.af >= T.perf.farm_ms then o.af = 0; draw_farm() end
    if o.at >= T.perf.text_ms then
        o.at = 0
        refresh_text()
        draw_kpi()
    end
    if o.ae >= T.perf.event_ms then o.ae = 0; draw_event() end
    if o.ac >= T.perf.curve_ms then
        o.ac = 0
        draw_curve()
        draw_rose()
    end

    -- 限电状态变了（自动窗口或外部写入），胶囊要跟着变
    if o.curtLast ~= data.state.curt then
        o.curtLast = data.state.curt
        draw_chip()
    end

    -- 无人操作：轮播选中机组
    o.idle = (o.idle or 0) + dt
    if o.idle > T.perf.auto_sec then
        o.idle = 0
        o.autoSel = true
        o.sel = (o.sel % data.N) + 1
        draw_farm()
        refresh_tiles()
    end

    -- 提示行每 6 秒换一句
    o.hintT = (o.hintT or 0) + dt
    if o.hintT > 6 then
        o.hintT = 0
        o.hintIdx = ((o.hintIdx or 1) % #HINTS) + 1
    end
end

-- 供 ui_main 读取：当前选中的机位（语音联想用）
function M.selected()
    return o.sel
end

return M
