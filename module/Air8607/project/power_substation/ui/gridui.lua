--[[
@module  gridui
@summary 工业风 UI：智慧配电房运维监测大屏
@version 1.0
@date    2026.10.26
@author  江访

=== 画面构成（1024x600）===
顶栏：标题 + 站名 + 日期 + 工况 + 大时钟
左列：主变运行（负载率环 + 4 行指标）/ 电量与需量（3 条用量条）
中列：电气主接线图（35kV 母线 - 主变 - 10kV 分段母线 - 6 条馈线）
      + 开关状态 / 环境安防 / 操作巡检 三张小卡
右列：实时告警（5 行滚动）/ 运行工况（遥测合格率 + 4 行电气量）
底栏：调度指令 / 巡检提醒 轮播

=== 刷新设计（跟 parkui 同一套节拍）===
每帧只有 2 个 44x44 告警脉冲 + 1 条潮流小条 + 6 个 14x14 状态点；
卡片各自一个 shape，500ms 轮转刷新一张；文本值变了才写。
]]

local fx = require "fx"
local T = require "theme"

local C, LY, SD = T.c, T.layout, T.sld
local LB = airui.TEXT_ALIGN_LEFT
local RA = airui.TEXT_ALIGN_RIGHT
local CA = airui.TEXT_ALIGN_CENTER
local SW, SH = T.screen.w, T.screen.h

local M = {}
local o          -- 界面状态（build 时初始化）
local CARD_FN    -- 卡片刷新函数表（轮转执行）

-- ==================== 时间基准 ====================
local HZ, HAS_T2 = 1000, false

local function init_time_base()
    if not mcu then return end
    if mcu.ticks2 then
        local ok, h = pcall(mcu.ticks2, 1)
        if ok and type(h) == "number" then HAS_T2 = true end
    end
    local hz = mcu.hz and mcu.hz()
    if type(hz) == "number" and hz >= 1 then HZ = hz end
    log.info("grid", string.format("时间基准 ticks2=%s mcu.hz()=%d", tostring(HAS_T2), HZ))
end

local function read_tick()
    if HAS_T2 then
        local h, l = mcu.ticks2(1)
        return h * 1000000 + l
    end
    if mcu and mcu.ticks then return mcu.ticks() end
    return nil
end

local function tick_ms(d)
    if HAS_T2 then return d end
    return d * 1000 / HZ
end

local function tick_delta(a, b)
    local d = a - b
    if d < 0 then
        if HAS_T2 then d = 0 else d = d + 4294967296 end
    end
    return d
end

-- ==================== 小工具 ====================
local function lbl(parent, x, y, w, h, text, size, color, align)
    return airui.label({
        parent = parent, x = x, y = y, w = w, h = h, text = text,
        font_size = size, color = color, align = align or LB,
    })
end

--[[文本缓存：LVGL 每次 set_text 都要重新排版并产生脏区，
70 多个文本节点不做缓存等于每秒几百次重排。]]
local function upd(key, node, v)
    if o.txt[key] ~= v then
        o.txt[key] = v
        node:set_text(v)
    end
end

-- 千分位：26,412
local function fmt3(n)
    local s = tostring(math.floor(n))
    if #s <= 3 then return s end
    local r = s:reverse():gsub("(%d%d%d)", "%1,")
    r = r:reverse()
    if r:sub(1, 1) == "," then r = r:sub(2) end
    return r
end

local function pad2(n)
    if n < 10 then return "0" .. n end
    return tostring(n)
end

-- ==================== 模拟数据 ====================
--[[数据全部由时间驱动（正弦 + 噪声），不存"上一帧值 + 随机增量"：
后者在长时间运行或掉帧时会漂到不合理区间，且没法复现。]]
local ALARM_POOL = {
    { place = "1#主变",     text = "绕组温度 71 C 偏高，加强冷却",      lv = "crit" },
    { place = "10kV I段",   text = "母线电压 10.72 kV 越上限",          lv = "warn" },
    { place = "馈线 水泵房", text = "断路器由合到分，遥控失败 1 次",    lv = "warn" },
    { place = "直流屏",     text = "蓄电池组电压偏低 216 V",            lv = "info" },
    { place = "分段开关",   text = "备自投动作成功，已恢复供电",        lv = "ok" },
    { place = "10kV II段",  text = "零序电流越限告警已复归",            lv = "ok" },
}

local NOTICE_POOL = {
    "调度指令：10kV II 段母线转检修，操作票已下发，值班员完成安全措施后执行",
    "巡检提醒：周五 09:00 对 1# 主变红外测温，保持安全距离，穿绝缘靴",
    "运行方式：单母线分段运行，分段开关热备用，备自投投入",
    "安全提示：SF6 气体浓度正常，进入电缆夹层前先通风 15 分钟",
}

local function step_data(t)
    local d = o.d
    local n1 = fx.noise1(t * 0.07)
    local n2 = fx.noise1(t * 0.23 + 3.1)
    local n3 = fx.noise1(t * 0.41 + 7.7)

    d.load1  = 0.62 + (n1 - 0.5) * 0.04
    d.load2  = 0.54 + (n2 - 0.5) * 0.04
    d.p      = 8642 + math.floor((n1 - 0.5) * 160)
    d.pf     = 0.960 + (n3 - 0.5) * 0.012
    d.oil    = 62 + math.floor((n1 - 0.5) * 3)
    d.wind   = 71 + math.floor((n2 - 0.5) * 3)

    d.energy  = 26412 + math.floor(t / 60) * 3
    d.peak_f  = 0.24
    d.valley_f = 0.46
    d.flat_f  = 0.30
    d.month   = 268412
    d.yoy     = -4.2

    d.sw_on, d.sw_all = 18, 20
    d.kn_on, d.kn_all = 24, 26
    d.gd_on, d.gd_all = 2, 8
    d.remote  = 1.0

    d.temp = 26 + math.floor((n3 - 0.5) * 2)
    d.hum  = 55 + math.floor((n1 - 0.5) * 4)
    d.sf6  = 0

    d.op, d.ticket, d.ticket_all = 3, 2, 2
    d.patrol, d.patrol_all = 8, 10

    d.pass_rate = 0.992 + (n2 - 0.5) * 0.004
    d.vbus  = 10.23 + (n1 - 0.5) * 0.06
    d.freq  = 50.01 + (n3 - 0.5) * 0.02
    d.vdc   = 220.4 + (n2 - 0.5) * 1.2
    d.signal = 12
end

-- ==================== 静态层 ====================
local function panel_bg(P, r, tint)
    --[[shape 画矩形是 x2 = x + w（含端点），所以宽高 -1 才正好铺满；
    顶部一条 1px 的强调色高光照出"玻璃面板"的厚度。]]
    P:box(r.x, r.y, r.w - 1, r.h - 1, C.panel, 250, 12)
    P:frame(r.x, r.y, r.w - 1, r.h - 1, C.line, 1, 255, 12)
    P:line(r.x + 14, r.y + 1, r.x + r.w - 15, r.y + 1, tint, 1, 80, true)
end

local function card_bar(P, r, tint)
    P:box(r.x + 16, r.y + 14, 3, 14, tint, 255, 1)
end

-- 电气主接线：图纸底 + 网格 + 35kV 母线 + 主变 + 10kV 分段母线 + 6 条馈线
local function draw_sld(P)
    local mx, my = LY.map.x + 16, LY.map.y + 44
    local w, h = SD.w, SD.h

    P:box(mx, my, w - 1, h - 1, 0x060C12, 255, 6)

    -- 网格（22px 一格，极低透明度，只做"有图纸感"的背景）
    for gx = 22, w - 4, 22 do
        P:line(mx + gx, my + 4, mx + gx, my + h - 5, C.grid, 1, 110)
    end
    for gy = 22, h - 4, 22 do
        P:line(mx + 4, my + gy, mx + w - 5, my + gy, C.grid, 1, 110)
    end

    -- 图框 + 四角定位角标
    P:frame(mx, my, w - 1, h - 1, 0x203447, 1, 255, 6)
    local ck = 14
    local corners = {
        { mx, my, 1, 1 }, { mx + w - 1, my, -1, 1 },
        { mx, my + h - 1, 1, -1 }, { mx + w - 1, my + h - 1, -1, -1 },
    }
    for _, c in ipairs(corners) do
        P:line(c[1], c[2], c[1] + ck * c[3], c[2], C.accent, 2, 170)
        P:line(c[1], c[2], c[1], c[2] + ck * c[4], C.accent, 2, 170)
    end

    -- 两路电源进线：箱体 + 引下线 + 进线断路器
    local ib = SD.in_box
    for _, x in ipairs(SD.in_x) do
        local bx = mx + x - ib.w / 2
        P:box(bx, my + ib.y, ib.w - 1, ib.h - 1, 0x0D1824, 255, 4)
        P:frame(bx, my + ib.y, ib.w - 1, ib.h - 1, C.line2, 1, 255, 4)
        P:line(x + mx - 18, my + ib.y + 1, x + mx + 18, my + ib.y + 1, C.accent, 1, 120, true)
        P:line(mx + x, my + ib.y + ib.h, mx + x, my + 42, C.line2, 2, 255)
        P:frame(mx + x - 6, my + 42, 12, 12, C.accent2, 1, 255, 2)
        P:box(mx + x - 4, my + 44, 8, 8, 0x0D1824, 255, 1)
        P:line(mx + x, my + 54, mx + x, my + SD.bus35_y, C.line2, 2, 255)
    end

    -- 35kV 母线（粗线 + 顶部高光）
    local b35 = SD.bus35_y
    P:line(mx + SD.bus35_x0, my + b35, mx + SD.bus35_x1, my + b35, 0x24405A, 4, 255)
    P:line(mx + SD.bus35_x0, my + b35 - 1, mx + SD.bus35_x1, my + b35 - 1, C.accent, 1, 110, true)

    -- 主变：两圆叠放的变压器符号 + 引上线
    for _, x in ipairs(SD.tx_x) do
        P:line(mx + x, my + b35, mx + x, my + SD.tx_cy[1] - SD.tx_r, C.line2, 2, 255)
        P:ring(mx + x, my + SD.tx_cy[1], SD.tx_r, C.accent2, 2, 255)
        P:ring(mx + x, my + SD.tx_cy[2], SD.tx_r, C.accent2, 2, 255)
        P:dot(mx + x, my + (SD.tx_cy[1] + SD.tx_cy[2]) / 2, 3, C.accent, 230)
        P:line(mx + x, my + SD.tx_cy[2] + SD.tx_r, mx + x, my + SD.bus10_y, C.line2, 2, 255)
    end

    -- 10kV 分段母线（两段粗线 + 中间分段断路器）
    local b10 = SD.bus10_y
    for _, seg in ipairs(SD.bus10) do
        P:line(mx + seg[1], my + b10, mx + seg[2], my + b10, 0x24405A, 4, 255)
        P:line(mx + seg[1], my + b10 - 1, mx + seg[2], my + b10 - 1, C.accent, 1, 110, true)
    end
    local tie = SD.tie
    P:frame(mx + tie.x, my + tie.y, tie.w - 1, tie.h - 1, C.accent2, 1, 255, 2)
    P:box(mx + tie.x + 2, my + tie.y + 2, tie.w - 5, tie.h - 5, 0x0D1824, 255, 1)

    -- 六条馈线：引下线 + 馈线断路器 + 负荷箱
    local fb = SD.feed_box
    for _, f in ipairs(SD.feeders) do
        P:line(mx + f.x, my + b10, mx + f.x, my + SD.feed_y1, C.line2, 2, 255)
        P:frame(mx + f.x - 5, my + 142, 10, 10, C.accent2, 1, 255, 2)
        P:box(mx + f.x - 3, my + 144, 6, 6, 0x0D1824, 255, 1)
        local bx = mx + f.x - fb.w / 2
        P:box(bx, my + fb.y, fb.w - 1, fb.h - 1, C.panel2, 255, 5)
        P:frame(bx, my + fb.y, fb.w - 1, fb.h - 1, 0x223A4E, 1, 255, 5)
        P:line(bx + 6, my + fb.y + 1, bx + fb.w - 7, my + fb.y + 1, C.accent, 1, 70, true)
    end
end

local function build_static()
    local P = fx.pool()
    P:reset()

    -- 底 + 顶栏 + 底栏
    P:box(0, 0, SW - 1, SH - 1, C.bg, 255, 0)
    P:box(0, 0, SW - 1, 55, 0x060B11, 255, 0)
    P:line(24, 55, SW - 25, 55, C.line, 1, 255)
    P:box(24, 16, 3, 22, C.accent, 255, 1)
    P:line(24, 42, 64, 42, C.accent, 1, 55)

    -- 顶栏分隔与工况图标（脉冲小波形）
    P:line(676, 18, 676, 38, C.line2, 1, 110)
    P:line(846, 16, 846, 40, C.line2, 1, 110)
    P:line(592, 26, 600, 26, C.green, 2, 220, true)
    P:line(600, 26, 605, 18, C.green, 2, 220, true)
    P:line(605, 18, 611, 34, C.green, 2, 220, true)
    P:line(611, 34, 616, 26, C.green, 2, 220, true)
    P:line(616, 26, 624, 26, C.green, 2, 220, true)

    -- 八张卡片底板
    panel_bg(P, LY.kpi, C.accent)
    panel_bg(P, LY.energy, C.amber)
    panel_bg(P, LY.map, C.accent)
    panel_bg(P, LY.card1, C.green)
    panel_bg(P, LY.card2, C.teal)
    panel_bg(P, LY.card3, C.violet)
    panel_bg(P, LY.alarm, C.red)
    panel_bg(P, LY.secu, C.blue)
    card_bar(P, LY.kpi, C.accent)
    card_bar(P, LY.energy, C.amber)
    card_bar(P, LY.map, C.accent)
    card_bar(P, LY.alarm, C.red)
    card_bar(P, LY.secu, C.blue)

    -- 电气主接线图（只画一次）
    draw_sld(P)

    -- 底栏
    P:box(0, LY.bottom_y, SW - 1, LY.bottom_y + LY.bottom_h - 1, 0x060B11, 255, 0)
    P:line(24, LY.bottom_y, SW - 25, LY.bottom_y, C.line, 1, 255)
    P:box(24, LY.bottom_y + 8, 3, 24, C.accent, 255, 1)

    P:finish()
    o.sh_static:set_items(P.items)
end

-- ==================== 动态层 ====================
local PIN  = fx.pool()   -- 告警点位脉冲
local FLOW = fx.pool()   -- 10kV 母线潮流亮点
local STAT = fx.pool()   -- 馈线状态点
local HL   = fx.pool()   -- 馈线巡览高亮

-- 告警点位脉冲：亮芯 + 3 圈扩散环，整体尺寸 44x44
local function draw_pin(i)
    local p = SD.pins[i]
    local t = o.t
    local b = 0.55 + 0.45 * math.sin(t * 3.4 + i * 1.7)   -- 亮度慢呼吸
    local spread = (t * 1.2 + i * 0.6) % 1                 -- 环快扩散
    local R = 22
    local items = PIN.items
    items[1] = { type = "circle", cx = R, cy = R, r = 4,
                 color = T.level[p.lv], width = 1, fill = true,
                 fill_color = T.level[p.lv], fill_opacity = math.floor(235 * b), segments = 22 }
    local r1 = 6 + spread * 8
    items[2] = { type = "circle", cx = R, cy = R, r = r1,
                 color = T.level[p.lv], width = 2,
                 opacity = math.floor((1 - spread) * 220 * b), segments = 24 }
    local r2 = 6 + ((spread + 0.5) % 1) * 8
    items[3] = { type = "circle", cx = R, cy = R, r = r2,
                 color = T.level[p.lv], width = 2,
                 opacity = math.floor((1 - (spread + 0.5) % 1) * 180 * b), segments = 24 }
    items[4] = { type = "circle", cx = R, cy = R, r = 14,
                 color = T.level[p.lv], width = 1,
                 opacity = math.floor(42 * b), segments = 24 }
    for j = 5, #items do items[j] = nil end
    o.pin_sh[i]:set_items(items)
end

-- 馈线状态点：合闸青绿 / 分闸灰蓝（14x14 小 shape，按帧更新）
local function draw_fdot(i)
    local P = STAT
    P:reset()
    local f = SD.feeders[i]
    local col = o.feed_on[i] and C.green or C.dim2
    P:dot(7, 7, 4, col, 255)
    P:finish()
    o.fdot_sh[i]:set_items(P.items)
end

-- 潮流亮点：沿 10kV 母线流动的 3 个小亮点
local function draw_flow()
    local P = FLOW
    P:reset()
    for k = 0, 2 do
        local x = (o.t * 160 + k * 106) % SD.flow.w
        P:dot(x, 7, 2, C.accent, 210)
    end
    P:finish()
    o.sh_flow:set_items(P.items)
end

-- 馈线巡览高亮：只框出当前馈线负荷箱
local function set_hl(i)
    local P = HL
    P:reset()
    local fb = SD.feed_box
    local f = SD.feeders[i]
    P:frame(0, 0, fb.w - 1, fb.h - 1, C.accent, 1, 120, 5)
    P:finish()
    o.hl_sh:set_items(P.items)
    o.hl_sh:set_x(LY.map.x + 16 + f.x - fb.w / 2)
    o.hl_sh:set_y(LY.map.y + 44 + fb.y)
end

-- ==================== 卡片刷新 ====================
--[[每张卡片一个 shape，画在自己的小坐标系里，好处是：
  1、进度条/环更新时只有该卡片局部重绘；
  2、shape 的 fill_color 直接当不透明底板，旧内容不会透出来。]]
local KPI  = fx.pool()
local ENG  = fx.pool()
local ALM  = fx.pool()
local SEC  = fx.pool()
local OP1  = fx.pool()
local OP2  = fx.pool()
local OP3  = fx.pool()

-- 主变运行：负载率环 + 功率因数条
local function draw_kpi()
    local d, P = o.d, KPI
    P:reset()
    -- 平均负载率环
    local frac = (d.load1 + d.load2) / 2
    P:arc(66, 120, 44, 135, 135 + 270 * fx.clamp(frac, 0, 1), C.accent, 10, 255, true)
    P:arc(66, 120, 44, 135 + 270 * fx.clamp(frac, 0, 1) + 8, 405, C.accent2, 10, 90, true)
    -- 功率因数条
    fx.meter(P, 110, 212, 86, 6, fx.clamp(d.pf, 0, 1), C.teal)
    P:finish()
    o.sh_kpi:set_items(P.items)
end

-- 电量与需量：峰 / 谷 / 平 三条用量条
local function draw_energy()
    local d, P = o.d, ENG
    P:reset()
    fx.meter(P, 48, 68,  120, 8, d.peak_f,   C.accent)
    fx.meter(P, 48, 108, 120, 8, d.valley_f, C.blue)
    fx.meter(P, 48, 148, 120, 8, d.flat_f,   C.amber)
    P:finish()
    o.sh_eng:set_items(P.items)
end

-- 实时告警：5 行等级色条（颜色不变，只画一次也行；这里跟 parkui 一致按卡片节奏重绘）
local function draw_alarm()
    local P = ALM
    P:reset()
    for i = 1, 5 do
        local a = ALARM_POOL[(o.alarm_idx + i - 1) % #ALARM_POOL + 1]
        local y = 50 + (i - 1) * 32
        P:box(16, y, 3, 22, T.level[a.lv], 255, 1)
    end
    P:finish()
    o.sh_alm:set_items(P.items)
end

-- 运行工况：遥测合格率条 + 4 个状态点
local function draw_secu()
    local d, P = o.d, SEC
    P:reset()
    fx.meter(P, 14, 74, 204, 6, fx.clamp(d.pass_rate, 0, 1), C.green)
    local cols = { C.green, C.green, C.green, C.green }
    for i = 1, 4 do
        P:dot(18, 103 + (i - 1) * 24, 3, cols[i], 255)
    end
    P:finish()
    o.sh_sec:set_items(P.items)
end

-- 开关状态：遥控投入率条
local function draw_c1()
    local d, P = o.d, OP1
    P:reset()
    fx.meter(P, 14, 96, 124, 6, fx.clamp(d.remote, 0, 1), C.green)
    P:finish()
    o.sh_c1:set_items(P.items)
end

-- 环境安防：湿度细条
local function draw_c2()
    local d, P = o.d, OP2
    P:reset()
    fx.meter(P, 14, 108, 124, 4, fx.clamp(d.hum / 100, 0, 1), C.teal)
    P:finish()
    o.sh_c2:set_items(P.items)
end

-- 操作巡检：巡检完成率条
local function draw_c3()
    local d, P = o.d, OP3
    P:reset()
    fx.meter(P, 14, 96, 124, 6, fx.clamp(d.patrol / d.patrol_all, 0, 1), C.violet)
    P:finish()
    o.sh_c3:set_items(P.items)
end

CARD_FN = {
    draw_kpi, draw_energy, draw_alarm, draw_secu, draw_c1, draw_c2, draw_c3,
}

-- ==================== 文本同步 ====================
local function sync_texts()
    local d, L = o.d, o.lb
    upd("online", L.online, "遥测在线 256/256")
    -- 主变运行
    upd("p", L.p, fmt3(d.p) .. " kW")
    upd("occ", L.occ, string.format("%d%%", math.floor((d.load1 + d.load2) / 2 * 100)))
    upd("v1", L.v1, string.format("%d%%", math.floor(d.load1 * 100)))
    upd("v2", L.v2, string.format("%d%%", math.floor(d.load2 * 100)))
    upd("v3", L.v3, string.format("%d C", d.oil))
    upd("v4", L.v4, string.format("%d C", d.wind))
    upd("target", L.target, string.format("%.2f", d.pf))
    -- 电量与需量
    upd("energy", L.energy, fmt3(d.energy) .. " kWh")
    upd("e1", L.e1, string.format("%d%%", d.peak_f * 100))
    upd("e2", L.e2, string.format("%d%%", d.valley_f * 100))
    upd("e3", L.e3, string.format("%d%%", d.flat_f * 100))
    upd("month", L.month, "本月 " .. fmt3(d.month) .. " kWh")
    upd("yoy", L.yoy, string.format("同比 %+.1f%%", d.yoy))
    -- 开关状态 / 环境安防 / 操作巡检
    upd("sw", L.sw, d.sw_on .. "/" .. d.sw_all)
    upd("kn", L.kn, d.kn_on .. "/" .. d.kn_all)
    upd("gd", L.gd, d.gd_on .. "/" .. d.gd_all)
    upd("sf6", L.sf6, tostring(d.sf6))
    upd("temp", L.temp, string.format("%d C", d.temp))
    upd("hum", L.hum, string.format("%d %%", d.hum))
    upd("water", L.water, "无")
    upd("todo", L.todo, tostring(d.op))
    upd("tk", L.tk, d.ticket .. "/" .. d.ticket_all)
    upd("pt", L.pt, d.patrol .. "/" .. d.patrol_all)
    -- 运行工况
    upd("pass_rate", L.pass_rate, string.format("%.1f%%", d.pass_rate * 100))
    upd("s1", L.s1, string.format("%.2f kV", d.vbus))
    upd("s2", L.s2, string.format("%.2f Hz", d.freq))
    upd("s3", L.s3, string.format("%.1f V", d.vdc))
    upd("s4", L.s4, string.format("%.3f", d.pf))
    upd("signal", L.pass, "今日遥信变位 " .. d.signal .. " 次")
    -- 实时告警（每行时间往前推）
    local now = os.time()
    for i = 1, 5 do
        local a = ALARM_POOL[(o.alarm_idx + i - 1) % #ALARM_POOL + 1]
        local tm = os.date("*t", now - (5 - i) * 47)
        upd("t" .. i, L["t" .. i], pad2(tm.hour) .. ":" .. pad2(tm.min))
        upd("p" .. i, L["p" .. i], a.place)
        upd("x" .. i, L["x" .. i], a.text)
    end
    upd("al_cnt", L.al_cnt, o.pending .. " 待处理")
    upd("notice", L.notice, NOTICE_POOL[o.notice_idx])
end

local function sync_clock()
    local L = o.lb
    local t = os.date("*t")
    upd("clock", L.clock, string.format("%02d:%02d", t.hour, t.min))
    upd("date", L.date, os.date("%Y-%m-%d %a %H:%M:%S"))
end

local function rotate_notice()
    o.notice_idx = (o.notice_idx % #NOTICE_POOL) + 1
end

local function rotate_alarm()
    o.alarm_idx = (o.alarm_idx + 1) % #ALARM_POOL
end

-- ==================== 组装 ====================
function M.build()
    o = {
        t = 0,
        d = {}, txt = {}, lb = {},
        feed_on = {}, fi = 0, card_i = 0,
        alarm_idx = 0, notice_idx = 1, pending = 5,
    }
    for i = 1, #SD.feeders do o.feed_on[i] = true end
    step_data(0)

    o.root = airui.container({ x = 0, y = 0, w = SW, h = SH })

    -- 底层：只画一次的静态层
    o.sh_static = airui.shape({ parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {} })
    build_static()

    -- 告警点位（2 个 44x44 脉冲）
    o.pin_sh = {}
    for i, p in ipairs(SD.pins) do
        o.pin_sh[i] = airui.shape({
            parent = o.root, w = 44, h = 44, items = {},
            x = LY.map.x + 16 + p.x - 22, y = LY.map.y + 44 + p.y - 22,
        })
    end

    -- 馈线状态点（6 个 14x14）
    o.fdot_sh = {}
    for i, f in ipairs(SD.feeders) do
        o.fdot_sh[i] = airui.shape({
            parent = o.root, w = 14, h = 14, items = {},
            x = LY.map.x + 16 + f.x - 7, y = LY.map.y + 44 + 153,
        })
    end

    -- 潮流小条（窄带流动亮点）
    o.sh_flow = airui.shape({
        parent = o.root, w = SD.flow.w, h = SD.flow.h, items = {},
        x = LY.map.x + 16 + SD.flow.x, y = LY.map.y + 44 + SD.flow.y,
    })

    -- 馈线巡览高亮框
    o.hl_sh = airui.shape({
        parent = o.root, w = SD.feed_box.w, h = SD.feed_box.h, items = {},
        x = LY.map.x + 16 + SD.feeders[1].x - SD.feed_box.w / 2,
        y = LY.map.y + 44 + SD.feed_box.y,
    })

    -- 卡片动态层（各自一个 shape，轮转刷新）
    o.sh_kpi = airui.shape({ parent = o.root, x = LY.kpi.x,    y = LY.kpi.y,    w = LY.kpi.w,    h = LY.kpi.h,    items = {} })
    o.sh_eng = airui.shape({ parent = o.root, x = LY.energy.x, y = LY.energy.y, w = LY.energy.w, h = LY.energy.h, items = {} })
    o.sh_alm = airui.shape({ parent = o.root, x = LY.alarm.x,  y = LY.alarm.y,  w = LY.alarm.w,  h = LY.alarm.h,  items = {} })
    o.sh_sec = airui.shape({ parent = o.root, x = LY.secu.x,   y = LY.secu.y,   w = LY.secu.w,   h = LY.secu.h,   items = {} })
    o.sh_c1  = airui.shape({ parent = o.root, x = LY.card1.x,  y = LY.card1.y,  w = LY.card1.w,  h = LY.card1.h,  items = {} })
    o.sh_c2  = airui.shape({ parent = o.root, x = LY.card2.x,  y = LY.card2.y,  w = LY.card2.w,  h = LY.card2.h,  items = {} })
    o.sh_c3  = airui.shape({ parent = o.root, x = LY.card3.x,  y = LY.card3.y,  w = LY.card3.w,  h = LY.card3.h,  items = {} })

    -- 图例小点（预警 / 异常 / 提示）
    local leg = { { 628, C.amber }, { 668, C.red }, { 708, C.accent } }
    for _, lg in ipairs(leg) do
        airui.shape({
            parent = o.root, x = lg[1], y = 78, w = 8, h = 8,
            items = { { type = "circle", cx = 4, cy = 4, r = 3,
                        color = lg[2], width = 1, fill = true,
                        fill_color = lg[2], fill_opacity = 255, segments = 16 } },
        })
    end

    -- 图例文字
    local leg_txt = { "预警", "异常", "提示" }
    for i = 1, 3 do
        lbl(o.root, 638 + (i - 1) * 40, 76, 26, 12, leg_txt[i], T.f.tiny, C.dim2, LB)
    end

    -- ==================== 文本 ====================
    local L = o.lb

    -- 顶栏
    lbl(o.root, 36, 6, 340, 24, "智慧配电房运维监测", T.f.title, C.txt, LB)
    lbl(o.root, 36, 30, 340, 12, "SMART SUBSTATION O&M TERMINAL", T.f.tiny, C.dim2, LB)
    lbl(o.root, 392, 10, 190, 16, "110kV 城南变电站", T.f.body, C.txt, LB)
    L.date  = lbl(o.root, 392, 30, 190, 12, "", T.f.small, C.dim, LB)
    lbl(o.root, 628, 18, 46, 12, "工况", T.f.mini, C.dim2, LB)
    lbl(o.root, 628, 32, 46, 12, "正常", T.f.small, C.green, LB)
    L.online = lbl(o.root, 692, 20, 148, 16, "", T.f.small, C.green, LB)
    L.clock  = lbl(o.root, 856, 10, 136, 32, "--:--", T.f.hero, C.txt, RA)

    -- 主变运行
    lbl(o.root, LY.kpi.x + 26, LY.kpi.y + 12, 150, 18, "主变运行", T.f.mid, C.txt, LB)
    lbl(o.root, LY.kpi.x + 26, LY.kpi.y + 30, 150, 12, "TRANSFORMER", T.f.tiny, C.dim2, LB)
    L.occ = lbl(o.root, LY.kpi.x + 34, LY.kpi.y + 106, 64, 26, "", T.f.title, C.accent, CA)
    lbl(o.root, LY.kpi.x + 26, LY.kpi.y + 132, 80, 12, "平均负载率", T.f.mini, C.dim2, CA)
    lbl(o.root, LY.kpi.x + 118, LY.kpi.y + 42, 100, 12, "有功功率", T.f.mini, C.dim, LB)
    L.p = lbl(o.root, LY.kpi.x + 118, LY.kpi.y + 54, 100, 20, "", T.f.big, C.txt, LB)
    local kname = { "1#主变负载", "2#主变负载", "上层油温", "绕组温度" }
    for i = 1, 4 do
        local y = LY.kpi.y + 88 + (i - 1) * 26
        lbl(o.root, LY.kpi.x + 118, y, 58, 12, kname[i], T.f.mini, C.dim, LB)
        L["v" .. i] = lbl(o.root, LY.kpi.x + 176, y - 2, 42, 16, "", T.f.small, C.txt, RA)
    end
    lbl(o.root, LY.kpi.x + 110, LY.kpi.y + 192, 58, 12, "功率因数", T.f.mini, C.dim, LB)
    L.target = lbl(o.root, LY.kpi.x + 176, LY.kpi.y + 190, 42, 16, "", T.f.small, C.teal, RA)

    -- 电量与需量
    lbl(o.root, LY.energy.x + 26, LY.energy.y + 12, 110, 18, "电量与需量", T.f.mid, C.txt, LB)
    lbl(o.root, LY.energy.x + 26, LY.energy.y + 30, 110, 12, "ENERGY", T.f.tiny, C.dim2, LB)
    L.energy = lbl(o.root, LY.energy.x + 112, LY.energy.y + 12, 104, 20, "", T.f.big, C.txt, RA)
    lbl(o.root, LY.energy.x + 16, LY.energy.y + 44, 100, 12, "分时占比", T.f.mini, C.dim2, LB)
    local ename = { "峰", "谷", "平" }
    for i = 1, 3 do
        local y = LY.energy.y + 64 + (i - 1) * 40
        lbl(o.root, LY.energy.x + 16, y, 28, 14, ename[i], T.f.small, C.dim, LB)
        L["e" .. i] = lbl(o.root, LY.energy.x + 170, y - 2, 42, 16, "", T.f.small, C.txt, RA)
    end
    L.month = lbl(o.root, LY.energy.x + 16, LY.energy.y + 186, 126, 14, "", T.f.small, C.dim, LB)
    L.yoy   = lbl(o.root, LY.energy.x + 144, LY.energy.y + 186, 68, 14, "", T.f.small, C.green, RA)

    -- 电气主接线
    lbl(o.root, LY.map.x + 26, LY.map.y + 12, 180, 18, "电气主接线", T.f.mid, C.txt, LB)
    lbl(o.root, LY.map.x + 26, LY.map.y + 30, 180, 12, "SINGLE LINE DIAGRAM", T.f.tiny, C.dim2, LB)
    -- 图内文字（绝对坐标 = map.x+16 + 图元 x，map.y+44 + 图元 y）
    lbl(o.root, 372, 118, 76, 12, "1#电源", T.f.tiny, C.dim2, CA)
    lbl(o.root, 576, 118, 76, 12, "2#电源", T.f.tiny, C.dim2, CA)
    lbl(o.root, 292, 148, 58, 12, "35kV", T.f.tiny, C.dim2, LB)
    lbl(o.root, 424, 188, 56, 12, "1#主变", T.f.mini, C.dim, LB)
    lbl(o.root, 628, 188, 56, 12, "2#主变", T.f.mini, C.dim, LB)
    lbl(o.root, 292, 232, 58, 12, "10kV I 段", T.f.tiny, C.dim2, LB)
    lbl(o.root, 672, 232, 60, 12, "10kV II 段", T.f.tiny, C.dim2, RA)
    lbl(o.root, 492, 248, 44, 12, "分段", T.f.tiny, C.dim2, CA)
    for _, f in ipairs(SD.feeders) do
        lbl(o.root, LY.map.x + 16 + f.x - 26, LY.map.y + 44 + SD.feed_box.y + 8,
            52, 12, f.name, T.f.mini, C.dim, CA)
    end

    -- 开关状态
    lbl(o.root, LY.card1.x + 14, LY.card1.y + 10, 124, 14, "开关状态", T.f.body, C.txt, LB)
    local c1n = { "断路器", "刀闸", "接地开关" }
    local c1k = { "sw", "kn", "gd" }
    for i = 1, 3 do
        local y = LY.card1.y + 30 + (i - 1) * 18
        lbl(o.root, LY.card1.x + 14, y, 50, 12, c1n[i], T.f.mini, C.dim, LB)
        L[c1k[i]] = lbl(o.root, LY.card1.x + 66, y - 2, 42, 16, "", T.f.small, C.txt, RA)
    end
    lbl(o.root, LY.card1.x + 14, LY.card1.y + 80, 80, 12, "遥控投入率", T.f.mini, C.dim, LB)

    -- 环境安防
    lbl(o.root, LY.card2.x + 14, LY.card2.y + 10, 124, 14, "环境安防", T.f.body, C.txt, LB)
    local c2n = { "SF6 气体", "温度", "湿度", "水浸" }
    local c2k = { "sf6", "temp", "hum", "water" }
    for i = 1, 4 do
        local y = LY.card2.y + 28 + (i - 1) * 16
        lbl(o.root, LY.card2.x + 14, y, 50, 12, c2n[i], T.f.mini, C.dim, LB)
        L[c2k[i]] = lbl(o.root, LY.card2.x + 66, y - 2, 42, 16, "", T.f.small, C.txt, RA)
    end
    lbl(o.root, LY.card2.x + 14, LY.card2.y + 92, 80, 12, "环境湿度", T.f.mini, C.dim, LB)

    -- 操作巡检
    lbl(o.root, LY.card3.x + 14, LY.card3.y + 10, 124, 14, "操作巡检", T.f.body, C.txt, LB)
    local c3n = { "待办操作", "操作票", "巡检进度" }
    local c3k = { "todo", "tk", "pt" }
    for i = 1, 3 do
        local y = LY.card3.y + 30 + (i - 1) * 18
        lbl(o.root, LY.card3.x + 14, y, 50, 12, c3n[i], T.f.mini, C.dim, LB)
        L[c3k[i]] = lbl(o.root, LY.card3.x + 66, y - 2, 42, 16, "", T.f.small, C.txt, RA)
    end
    lbl(o.root, LY.card3.x + 14, LY.card3.y + 84, 80, 12, "巡检完成率", T.f.mini, C.dim, LB)

    -- 实时告警
    lbl(o.root, LY.alarm.x + 26, LY.alarm.y + 12, 100, 18, "实时告警", T.f.mid, C.txt, LB)
    lbl(o.root, LY.alarm.x + 26, LY.alarm.y + 30, 100, 12, "ALARM", T.f.tiny, C.dim2, LB)
    L.al_cnt = lbl(o.root, LY.alarm.x + 126, LY.alarm.y + 12, 90, 16, "", T.f.small, C.red, RA)
    for i = 1, 5 do
        local y = LY.alarm.y + 50 + (i - 1) * 32
        L["t" .. i] = lbl(o.root, LY.alarm.x + 24, y, 34, 12, "", T.f.tiny, C.dim2, LB)
        L["p" .. i] = lbl(o.root, LY.alarm.x + 62, y, 72, 12, "", T.f.mini, C.dim, LB)
        L["x" .. i] = lbl(o.root, LY.alarm.x + 24, y + 13, 192, 12, "", T.f.mini, C.txt, LB)
    end

    -- 运行工况
    lbl(o.root, LY.secu.x + 26, LY.secu.y + 12, 110, 18, "运行工况", T.f.mid, C.txt, LB)
    lbl(o.root, LY.secu.x + 26, LY.secu.y + 30, 110, 12, "OPERATION", T.f.tiny, C.dim2, LB)
    lbl(o.root, LY.secu.x + 16, LY.secu.y + 52, 76, 14, "遥测合格率", T.f.mini, C.dim, LB)
    L.pass_rate = lbl(o.root, LY.secu.x + 140, LY.secu.y + 48, 76, 20, "", T.f.big, C.green, RA)
    local sname = { "母线电压", "系统频率", "直流电压", "功率因数" }
    for i = 1, 4 do
        local y = LY.secu.y + 96 + (i - 1) * 24
        lbl(o.root, LY.secu.x + 30, y, 80, 14, sname[i], T.f.mini, C.dim, LB)
        L["s" .. i] = lbl(o.root, LY.secu.x + 130, y - 2, 86, 16, "", T.f.small, C.txt, RA)
    end
    L.pass = lbl(o.root, LY.secu.x + 16, LY.secu.y + 190, 200, 14, "", T.f.small, C.dim, LB)

    -- 底栏
    L.notice = lbl(o.root, 36, LY.bottom_y + 10, 700, 20, "", T.f.body, C.dim, LB)
    lbl(o.root, 744, LY.bottom_y + 13, 248, 14, "数据每 2 秒刷新 / 256 台设备在线",
        T.f.tiny, C.dim2, RA)

    -- 首屏铺一次
    draw_kpi()
    draw_energy()
    draw_alarm()
    draw_secu()
    draw_c1()
    draw_c2()
    draw_c3()
    for i = 1, #SD.pins do draw_pin(i) end
    for i = 1, #SD.feeders do draw_fdot(i) end
    draw_flow()
    set_hl(1)
    sync_texts()
    sync_clock()
    log.info("gridui", "界面构建完成")
end

-- ==================== 主循环 ====================
function M.run()
    init_time_base()

    local t = 0
    local prev = read_tick()
    local cardT, textT, clockT, noticeT, hlT = 0, 0, 0, 0, 0
    local avgN = (HAS_T2 or HZ >= 200) and 4 or 8
    local accMs, accN = 0, 0
    local dtMs = T.perf.frame_ms

    while true do
        sys.wait(T.perf.frame_ms)

        local now = read_tick()
        if now and prev then
            local rawMs = tick_ms(tick_delta(now, prev))
            prev = now
            if rawMs > 250 then rawMs = 250 end
            if rawMs < 0 then rawMs = 0 end
            accMs = accMs + rawMs
            accN = accN + 1
            if accN >= avgN then
                dtMs = accMs / accN
                accMs, accN = 0, 0
            end
        end
        local dt = dtMs / 1000
        if dt > 0.2 then dt = 0.2 elseif dt < 0.004 then dt = 0.004 end

        t = t + dt
        o.t = t
        step_data(t)

        -- 每帧：2 个告警脉冲 + 1 条潮流小条 + 6 个馈线状态点
        for i = 1, #SD.pins do draw_pin(i) end
        draw_flow()
        for i = 1, #SD.feeders do draw_fdot(i) end

        -- 卡片轮转：一次只重画一张
        cardT = cardT + dt
        if cardT >= T.perf.card_ms / 1000 then
            cardT = 0
            o.card_i = o.card_i % #CARD_FN + 1
            local ok, err = pcall(CARD_FN[o.card_i])
            if not ok then log.error("gridui", "卡片刷新异常", err) end
        end

        -- 文本：值变了才写
        textT = textT + dt
        if textT >= T.perf.text_ms / 1000 then
            textT = 0
            local ok, err = pcall(sync_texts)
            if not ok then log.error("gridui", "文本刷新异常", err) end
        end

        -- 时钟
        clockT = clockT + dt
        if clockT >= T.perf.hz_ms / 1000 then
            clockT = 0
            sync_clock()
        end

        -- 通知与告警滚动
        noticeT = noticeT + dt
        if noticeT >= T.perf.notice_ms / 1000 then
            noticeT = 0
            rotate_notice()
            rotate_alarm()
            draw_alarm()
        end

        -- 馈线巡览高亮
        hlT = hlT + dt
        if hlT >= T.perf.hl_ms / 1000 then
            hlT = 0
            o.fi = o.fi % #SD.feeders + 1
            set_hl(o.fi)
        end
    end
end

return M
