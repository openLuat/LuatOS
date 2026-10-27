--[[
@module  park
@summary 智慧工业园区管理平台 · 主界面
@version 1.0
@date    2026.10.25
@author  江访

=== 画面构成（1024x600，零图片素材）===
  顶栏：平台名 / 日期 / 天气 / 设备在线 / 时钟
  左列：园区总览（入驻率环 + 4 项指标 + 月度目标条）、能耗监测（电/水/气三条）
  中列：园区实时态势（程序化平面图 + 告警点位脉冲 + 建筑巡览高亮）、三张服务小卡
  右列：实时告警（5 条分级）、安防与通行（在线率 + 四类设备）
  底栏：轮播通知 + 刷新提示

=== 性能设计（真机是 PSRAM 帧缓冲、无 GPU）===
1. 分层：静态层（底图/卡片底板/地图/刻度/表槽）只画一次；
   每张卡的动态部分各自一个 shape，按 300ms 轮转刷新，一次只重画一张卡；
   告警点位是三个 44x44 的小 shape，每帧只动它们；
   建筑高亮是每栋一个小 shape，2.6 秒换一栋。
2. 地图里的"扫描线 / 旋转雷达"这类整块区域的动画一律不做 ——
   那块 440x288 每帧重画一次，真机直接掉到个位数帧率。
3. 文字全部走 upd() 缓存，值不变就不 set_text；LVGL 的 set_text 会重排文本并产生脏区。
4. 时间基准优先 mcu.ticks2(1)（64 位毫秒），否则 mcu.ticks()+mcu.hz() 并做回绕补偿；
   注意 mcu 是 rotable，type() 返回 "userdata"，不能用 type()=="table" 做守卫。
]]
local fx = require "fx"
local T = require "theme"

local M = {}
local C, LY, MP = T.c, T.layout, T.map
local SW, SH = T.screen.w, T.screen.h
local LB, RA, CA = airui.TEXT_ALIGN_LEFT, airui.TEXT_ALIGN_RIGHT, airui.TEXT_ALIGN_CENTER

local o                     -- 运行期状态
local CARD_FN               -- 卡片刷新函数表（轮转执行）

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
    log.info("park", string.format("时间基准 ticks2=%s mcu.hz()=%d", tostring(HAS_T2), HZ))
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
园区大屏有 70 多个文本节点，不做缓存等于每秒几百次重排。]]
local function upd(key, node, v)
    if o.txt[key] ~= v then
        o.txt[key] = v
        node:set_text(v)
    end
end

-- 千分位：12,480
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
--[[园区数据全部由时间驱动（正弦 + 噪声），不存"上一帧值 + 随机增量"：
后者在长时间运行或掉帧时会漂到不合理区间，且没法复现。]]
local ALARM_POOL = {
    { place = "B 中试车间", text = "3 号注塑机温度偏高 86 C", lv = "crit" },
    { place = "D 综合办公", text = "3 层门禁连续 3 次刷卡失败", lv = "warn" },
    { place = "I 停车区",   text = "剩余车位 12 个，接近饱和",   lv = "info" },
    { place = "C 仓储中心", text = "东侧卷帘未按计划关闭",       lv = "warn" },
    { place = "E 数据机房", text = "UPS 负载 82%，已恢复",       lv = "ok"   },
    { place = "A 研发楼",   text = "消防喷淋压力恢复正常",       lv = "ok"   },
}

local NOTICE_POOL = {
    "园区管委会：10 月 26 日 08:00 在 B 区开展消防疏散演练，请各部门提前通知到人",
    "物业提醒：本周六 22:00-24:00 对 C 区仓储进行高压配电年检，期间电梯停运",
    "运营通知：园区新能源车位已扩容至 48 个，扫码即充，前两小时免服务费",
    "安全提示：今日阵风 6 级，请各单位检查外墙广告牌与阳台物品",
}

local function step_data(t)
    local d = o.d
    local n1 = fx.noise1(t * 0.07)
    local n2 = fx.noise1(t * 0.23 + 3.1)
    local n3 = fx.noise1(t * 0.41 + 7.7)

    d.occ       = 0.86 + (n1 - 0.5) * 0.02
    d.tenants   = 128
    d.staff     = 12480 + math.floor((n1 - 0.5) * 60)
    d.visitors  = 326 + math.floor(t / 40) % 30
    d.cars      = 214 + math.floor((n2 - 0.5) * 24)
    d.target    = 0.78 + n2 * 0.02

    d.energy    = 8942 + math.floor((n1 - 0.5) * 120)
    d.elec, d.water, d.gas = 0.62, 0.24, 0.14
    d.month     = 268412
    d.yoy       = -4.2

    d.inflow    = 1286 + math.floor((n2 - 0.5) * 20)
    d.outflow   = 1204 + math.floor((n3 - 0.5) * 18)
    d.manual    = 86
    d.etc       = 942
    d.temp_car  = 258

    d.pm25      = 32 + math.floor((n1 - 0.5) * 8)
    d.noise     = 52 + math.floor((n2 - 0.5) * 6)
    d.temp      = 26
    d.hum       = 58

    d.todo      = 7
    d.doing     = 3
    d.done      = 42 + math.floor(t / 60) % 5
    d.done_rate = 0.86

    d.sec_rate  = 0.965
    d.pass      = 3842 + math.floor(t / 30) % 40
    d.online    = 386
    d.total     = 400
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

-- 地图：底 + 网格 + 围墙 + 道路 + 建筑 + 绿化 + 车位
local function draw_map(P)
    local mx, my = LY.map.x + 16, LY.map.y + 44
    local w, h = MP.w, MP.h

    P:box(mx, my, w - 1, h - 1, 0x060C12, 255, 6)

    -- 网格（22px 一格，极低透明度，只做"有坐标感"的背景）
    for gx = 22, w - 4, 22 do
        P:line(mx + gx, my + 4, mx + gx, my + h - 5, C.grid, 1, 110)
    end
    for gy = 22, h - 4, 22 do
        P:line(mx + 4, my + gy, mx + w - 5, my + gy, C.grid, 1, 110)
    end

    -- 围墙 + 四角定位角标
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

    -- 主干道
    local rv, rh = MP.road_v, MP.road_h
    P:box(mx + rv.x, my, rv.w, h - 1, 0x0A131C, 255, 0)
    P:box(mx, my + rh.y, w - 1, rh.h, 0x0A131C, 255, 0)
    P:line(mx + rv.x, my, mx + rv.x, my + h - 1, 0x16283A, 1, 255)
    P:line(mx + rv.x + rv.w, my, mx + rv.x + rv.w, my + h - 1, 0x16283A, 1, 255)
    P:line(mx, my + rh.y, mx + w - 1, my + rh.y, 0x16283A, 1, 255)
    P:line(mx, my + rh.y + rh.h, mx + w - 1, my + rh.y + rh.h, 0x16283A, 1, 255)
    -- 车道虚线
    for gy = 6, h - 12, 18 do
        P:line(mx + rv.x + rv.w / 2, my + gy, mx + rv.x + rv.w / 2, my + gy + 9, 0x24405A, 2, 210)
    end
    for gx = 6, w - 12, 18 do
        P:line(mx + gx, my + rh.y + rh.h / 2, mx + gx + 9, my + rh.y + rh.h / 2, 0x24405A, 2, 210)
    end

    -- 建筑
    for _, b in ipairs(MP.buildings) do
        local k = T.kind[b.kind]
        local x, y = mx + b.x, my + b.y
        if b.kind == "green" then
            P:box(x, y, b.w - 1, b.h - 1, k.fill, 230, 6)
            P:frame(x, y, b.w - 1, b.h - 1, k.edge, 1, 200, 6)
        else
            P:box(x, y, b.w - 1, b.h - 1, k.fill, 245, 3)
            P:frame(x, y, b.w - 1, b.h - 1, k.edge, 1, 255, 3)
            -- 顶部高光：一条 2px 的亮边，立刻有"楼顶受光"的立体感
            P:line(x + 5, y + 2, x + b.w - 7, y + 2, k.top, 2, 120, true)
            -- 楼内两道淡淡的分层线，远看像楼层/产线，避免大片死黑
            if b.h > 40 then
                P:line(x + 6, y + math.floor(b.h * 0.45), x + b.w - 8, y + math.floor(b.h * 0.45), k.edge, 1, 90)
            end
            if b.h > 52 then
                P:line(x + 6, y + math.floor(b.h * 0.68), x + b.w - 8, y + math.floor(b.h * 0.68), k.edge, 1, 70)
            end
        end
    end

    -- 绿化广场里的小树（无阴影，纯点 + 一圈淡光晕）
    for _, tr in ipairs(MP.trees) do
        P:dot(mx + tr[1], my + tr[2], tr[3] + 2, C.teal, 40)
        P:dot(mx + tr[1], my + tr[2], tr[3], C.teal, 150)
    end

    -- 停车位：一排短竖线
    for sx = 240, 420, 23 do
        P:line(mx + sx, my + 178, mx + sx, my + 208, 0x1B2E3E, 1, 220)
    end
    P:line(mx + 232, my + 193, mx + 432, my + 193, 0x1B2E3E, 1, 160)
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

    -- 顶栏分隔与天气图标
    P:line(676, 18, 676, 38, C.line2, 1, 110)
    P:line(846, 16, 846, 40, C.line2, 1, 110)
    P:dot(596, 26, 6, C.amber, 235)
    for i = 0, 7 do
        local a = i * 45
        local c, s = math.cos(math.rad(a)), math.sin(math.rad(a))
        P:line(596 + c * 9, 26 + s * 9, 596 + c * 13, 26 + s * 13, C.amber, 1, 170, true)
    end

    -- 七张卡片底板
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
    card_bar(P, LY.card1, C.green)
    card_bar(P, LY.card2, C.teal)
    card_bar(P, LY.card3, C.violet)
    card_bar(P, LY.alarm, C.red)
    card_bar(P, LY.secu, C.blue)

    -- 四张大卡右上角的"在线"小点，让一排卡片有统一的收尾
    P:dot(LY.kpi.x + 216, LY.kpi.y + 20, 3, C.green, 200)
    P:dot(LY.energy.x + 216, LY.energy.y + 20, 3, C.green, 200)
    P:dot(LY.secu.x + 216, LY.secu.y + 20, 3, C.green, 200)

    -- 入驻率环的轨道 + 外圈细环（进度弧在卡片层里）
    P:ring(LY.kpi.x + 66, LY.kpi.y + 120, 44, 0x101B26, 10, 255)
    P:ring(LY.kpi.x + 66, LY.kpi.y + 120, 52, 0x1A2E3E, 1, 140)

    -- 地图
    draw_map(P)

    -- 地图图例：和点位等级一一对应（警示 / 异常 / 提示）
    P:dot(LY.map.x + 352, LY.map.y + 18, 3, C.amber, 235)
    P:dot(LY.map.x + 392, LY.map.y + 18, 3, C.red, 235)
    P:dot(LY.map.x + 432, LY.map.y + 18, 3, C.accent, 235)

    --[[告警卡行的分隔线：第 i 行占 52+(i-1)*34 起、高 30，
    所以第 i 行下面的线在 82+(i-1)*34（不是 52+i*34，那样会整整错开一行）]]
    for i = 1, 4 do
        local y = LY.alarm.y + 78 + (i - 1) * 32
        P:line(LY.alarm.x + 16, y, LY.alarm.x + 216, y, 0x121C26, 1, 180)
    end

    -- 安防卡：在线率表槽 + 四类设备的分隔
    P:box(LY.secu.x + 16, LY.secu.y + 74, 200, 8, 0x101A26, 220, 4)
    P:line(LY.secu.x + 16, LY.secu.y + 88, LY.secu.x + 216, LY.secu.y + 88, 0x121C26, 1, 160)

    -- 能耗卡：三条表槽 + 底部两栏分隔
    for i = 1, 3 do
        local y = LY.energy.y + 64 + (i - 1) * 40
        P:box(LY.energy.x + 48, y + 4, 120, 8, 0x101A26, 220, 4)
    end
    P:line(LY.energy.x + 16, LY.energy.y + 182, LY.energy.x + 216, LY.energy.y + 182, 0x121C26, 1, 180)

    -- 服务小卡：工单完成率表槽、PM2.5 表槽（PM2.5 的表槽要放在三行文字下面，别压住"湿度"）
    P:box(LY.card3.x + 14, LY.card3.y + 96, 124, 6, 0x101A26, 220, 3)
    P:box(LY.card2.x + 14, LY.card2.y + 108, 124, 4, 0x101A26, 200, 2)

    -- 底栏
    P:line(24, LY.bottom_y, SW - 25, LY.bottom_y, C.line, 1, 220)
    P:dot(30, LY.bottom_y + 20, 3, C.amber, 230)

    P:finish()
    o.sh_static:set_items(P.items)
end

-- ==================== 告警点位 + 建筑高亮 ====================
local PIN, HL = fx.pool(), fx.pool()
local PINBOX = 44

local function draw_pin(i)
    local p = o.pins[i]
    local col = T.level[p.lv]
    local P = PIN
    local c = PINBOX / 2
    local ph = (o.t * 0.55 + i * 0.33) % 1
    P:reset()
    P:dot(c, c, 4, col, 255)
    P:ring(c, c, 5 + ph * 13, col, 2, math.floor(190 * (1 - ph)))
    P:finish()
    p.s:set_items(P.items)
end

local function set_hl(i)
    if o.hl == i then return end
    local prev = o.hl
    o.hl = i
    if prev then
        HL:reset(); HL:finish()
        o.hlsh[prev]:set_items(HL.items)
    end
    if i then
        local b = MP.buildings[i]
        HL:reset()
        HL:frame(0, 0, b.w - 1, b.h - 1, C.accent, 1, 220, 3)
        HL:frame(2, 2, b.w - 5, b.h - 5, C.accent, 1, 60, 2)
        HL:finish()
        o.hlsh[i]:set_items(HL.items)
    end
end

-- ==================== 卡片（轮转刷新） ====================
local KPI, ENG, ALM, SEC, SVC2, SVC3 = fx.pool(), fx.pool(), fx.pool(), fx.pool(), fx.pool(), fx.pool()

--[[注意：卡片有自己的 shape，图元坐标是"相对卡片左上角"的，
所以这里一律用卡片内局部坐标（16/48/66…），不要再加 LY.xxx.x/y。]]
local function draw_kpi()
    local P = KPI
    local d = o.d
    P:reset()
    P:arc(66, 120, 44, 135, 135 + 270 * fx.clamp(d.occ, 0, 1), C.accent, 10, 255, true)
    fx.meter(P, 110, 212, 86, 6, d.target, C.teal)
    P:finish()
    o.sh_kpi:set_items(P.items)
end

local function draw_energy()
    local P = ENG
    local d = o.d
    P:reset()
    fx.meter(P, 48, 68, 120, 8, d.elec, C.accent)
    fx.meter(P, 48, 108, 120, 8, d.water, C.blue)
    fx.meter(P, 48, 148, 120, 8, d.gas, C.amber)
    P:finish()
    o.sh_en:set_items(P.items)
end

local function draw_alarm()
    local P = ALM
    P:reset()
    for i = 1, 5 do
        local a = o.alarms[i]
        P:box(16, 50 + (i - 1) * 32, 3, 22, T.level[a.lv], 255, 1)
    end
    P:finish()
    o.sh_al:set_items(P.items)
end

local function draw_secu()
    local P = SEC
    local d = o.d
    P:reset()
    fx.meter(P, 16, 74, 200, 8, d.sec_rate, C.green)
    for i = 1, #o.sec do
        P:dot(22, 96 + (i - 1) * 24 + 7, 3, o.sec[i].col, 240)
    end
    P:finish()
    o.sh_se:set_items(P.items)
end

local function draw_svc2()
    local P = SVC2
    P:reset()
    fx.meter(P, 14, 108, 124, 4, fx.clamp(o.d.pm25 / 100, 0, 1), C.teal)
    P:finish()
    o.sh_c2:set_items(P.items)
end

local function draw_svc3()
    local P = SVC3
    P:reset()
    fx.meter(P, 14, 96, 124, 6, o.d.done_rate, C.violet)
    P:finish()
    o.sh_c3:set_items(P.items)
end

CARD_FN = { draw_kpi, draw_energy, draw_alarm, draw_secu, draw_svc2, draw_svc3 }

-- ==================== 文本 ====================
local WEEK = { "周日", "周一", "周二", "周三", "周四", "周五", "周六" }

local function sync_texts()
    local d, L = o.d, o.lb
    upd("occ", L.occ, string.format("%d%%", math.floor(d.occ * 100 + 0.5)))
    upd("tenants", L.v1, fmt3(d.tenants))
    upd("staff", L.v2, fmt3(d.staff))
    upd("visitors", L.v3, fmt3(d.visitors))
    upd("cars", L.v4, fmt3(d.cars))
    upd("target", L.target, string.format("%d%%", math.floor(d.target * 100 + 0.5)))

    upd("energy", L.today, fmt3(d.energy) .. " kWh")
    upd("elec", L.e1, string.format("%d%%", math.floor(d.elec * 100 + 0.5)))
    upd("water", L.e2, string.format("%d%%", math.floor(d.water * 100 + 0.5)))
    upd("gas", L.e3, string.format("%d%%", math.floor(d.gas * 100 + 0.5)))
    upd("month", L.month, "本月 " .. fmt3(d.month) .. " kWh")
    upd("yoy", L.yoy, string.format("同比 %.1f%%", d.yoy))

    upd("inflow", L.inflow, fmt3(d.inflow))
    upd("outflow", L.outflow, fmt3(d.outflow))
    upd("manual", L.manual, tostring(d.manual))
    upd("etc", L.etc, tostring(d.etc))
    upd("temp_car", L.tempc, tostring(d.temp_car))

    upd("pm25", L.pm25, tostring(d.pm25))
    upd("pmq", L.pmq, (d.pm25 <= 35) and "PM2.5 优" or "PM2.5 良")
    upd("noise", L.noise, tostring(d.noise) .. " dB")
    upd("temp", L.temp, tostring(d.temp) .. " C")
    upd("hum", L.hum, tostring(d.hum) .. " %")

    upd("todo", L.todo, tostring(d.todo))
    upd("doing", L.doing, tostring(d.doing))
    upd("done", L.done, tostring(d.done))

    upd("sec_rate", L.sec_rate, string.format("%.1f%%", d.sec_rate * 100))
    for i = 1, #o.sec do
        local s = o.sec[i]
        upd("sec" .. i, s.lb, string.format("%d/%d", s.n, s.m))
    end
    upd("pass", L.pass, "今日通行 " .. fmt3(d.pass) .. " 人次")

    upd("online", L.online, string.format("设备在线 %d/%d", d.online, d.total))

    -- 告警列表
    local cnt = 0
    for i = 1, 5 do
        local a = o.alarms[i]
        local row = o.al_row[i]
        upd("al_t" .. i, row.t, a.t)
        upd("al_p" .. i, row.p, a.place)
        upd("al_x" .. i, row.x, a.text)
        if a.lv == "crit" or a.lv == "warn" then cnt = cnt + 1 end
    end
    upd("al_cnt", L.al_cnt, string.format("%d 待处理", cnt))
    upd("notice", L.notice, o.notice)
end

local function sync_clock()
    local t = os.date("*t")
    if not t then return end
    upd("clock", o.lb.clock, string.format("%02d:%02d", t.hour, t.min))
    upd("date", o.lb.date, string.format("%04d-%02d-%02d %s",
        t.year, t.month, t.day, WEEK[(t.wday % 7) + 1] or ""))
end

local function rotate_notice()
    o.ni = o.ni % #NOTICE_POOL + 1
    o.notice = NOTICE_POOL[o.ni]
end

local function rotate_alarm()
    local t = os.date("*t")
    local stamp = t and string.format("%02d:%02d", t.hour, t.min) or "08:00"
    o.ai = o.ai % #ALARM_POOL + 1
    local src = ALARM_POOL[o.ai]
    -- 新告警插到最上面，其余下移一位
    for i = 5, 2, -1 do
        o.alarms[i] = o.alarms[i - 1]
    end
    o.alarms[1] = { t = stamp, place = src.place, text = src.text, lv = src.lv }
end

-- ==================== 构建 ====================
function M.build()
    o = {
        txt = {}, lb = {}, al_row = {},
        t = 0,
        d = { sec_rate = 0.96 },
        sec = {
            { n = 128, m = 132, col = C.green },
            { n = 46,  m = 46,  col = C.green },
            { n = 87,  m = 90,  col = C.amber },
            { n = 25,  m = 26,  col = C.green },
        },
        alarms = {}, cards = {},
        -- ai 从 1 起：首屏已经显示了 ALARM_POOL[1]，第一次滚动应该插第 2 条
        ni = 0, ai = 1, hl = nil, card_i = 0,
        notice = NOTICE_POOL[1],
    }

    o.root = airui.container({
        parent = nil, x = 0, y = 0, w = SW, h = SH,
        color = C.bg, color_opacity = 255, radius = 0, border_width = 0,
    })

    -- 静态层
    o.sh_static = airui.shape({ parent = o.root, x = 0, y = 0, w = SW, h = SH, items = {} })

    --[[告警初值：5 条，时间从当前时刻往前每 23 分钟一条 ——
    必须是递减的，否则列表看起来像"时间乱序"。]]
    local t = os.date("*t")
    local now_min = (t and (t.hour * 60 + t.min)) or 9 * 60
    for i = 1, 5 do
        local src = ALARM_POOL[(i - 1) % #ALARM_POOL + 1]
        local m = (now_min - (i - 1) * 23) % 1440
        o.alarms[i] = {
            t = string.format("%02d:%02d", math.floor(m / 60), m % 60),
            place = src.place, text = src.text, lv = src.lv,
        }
    end

    build_static()

    -- 卡片动态层（各自一个 shape，轮转刷新）
    o.sh_kpi = airui.shape({ parent = o.root, x = LY.kpi.x, y = LY.kpi.y, w = LY.kpi.w, h = LY.kpi.h, items = {} })
    o.sh_en  = airui.shape({ parent = o.root, x = LY.energy.x, y = LY.energy.y, w = LY.energy.w, h = LY.energy.h, items = {} })
    o.sh_al  = airui.shape({ parent = o.root, x = LY.alarm.x, y = LY.alarm.y, w = LY.alarm.w, h = LY.alarm.h, items = {} })
    o.sh_se  = airui.shape({ parent = o.root, x = LY.secu.x, y = LY.secu.y, w = LY.secu.w, h = LY.secu.h, items = {} })
    o.sh_c2  = airui.shape({ parent = o.root, x = LY.card2.x, y = LY.card2.y, w = LY.card2.w, h = LY.card2.h, items = {} })
    o.sh_c3  = airui.shape({ parent = o.root, x = LY.card3.x, y = LY.card3.y, w = LY.card3.w, h = LY.card3.h, items = {} })

    -- 告警点位（小方块，每帧脉冲）
    o.pins = {}
    for i, p in ipairs(MP.pins) do
        local s = airui.shape({
            parent = o.root,
            x = LY.map.x + 16 + p.x - PINBOX / 2,
            y = LY.map.y + 44 + p.y - PINBOX / 2,
            w = PINBOX, h = PINBOX, items = {},
        })
        o.pins[i] = { s = s, lv = p.lv }
    end

    -- 建筑巡览高亮（每栋一个 shape，切换时只改两块）
    o.hlsh = {}
    for i, b in ipairs(MP.buildings) do
        o.hlsh[i] = airui.shape({
            parent = o.root,
            x = LY.map.x + 16 + b.x, y = LY.map.y + 44 + b.y,
            w = b.w, h = b.h, items = {},
        })
    end

    -- ==================== 文本 ====================
    local L = o.lb
    -- 顶栏
    lbl(o.root, 34, 12, 380, 26, "智慧工业园区管理平台", T.f.title, C.txt, LB)
    lbl(o.root, 34, 38, 240, 12, "SMART INDUSTRIAL PARK", T.f.tiny, C.dim2, LB)
    L.date    = lbl(o.root, 392, 20, 180, 16, "", T.f.body, C.dim, LB)
    L.weather = lbl(o.root, 604, 19, 48, 18, "22 C", T.f.num, C.txt, RA)
    L.online  = lbl(o.root, 686, 20, 140, 16, "", T.f.small, C.dim, RA)
    L.clock   = lbl(o.root, 856, 10, 136, 32, "--:--", T.f.hero, C.txt, RA)

    -- 园区总览
    lbl(o.root, LY.kpi.x + 26, LY.kpi.y + 12, 120, 18, "园区总览", T.f.mid, C.txt, LB)
    lbl(o.root, LY.kpi.x + 26, LY.kpi.y + 30, 120, 12, "OVERVIEW", T.f.tiny, C.dim2, LB)
    L.occ     = lbl(o.root, LY.kpi.x + 36, LY.kpi.y + 104, 60, 24, "86%", T.f.title, C.accent, CA)
    lbl(o.root, LY.kpi.x + 36, LY.kpi.y + 130, 60, 12, "入驻率", T.f.tiny, C.dim2, CA)
    --[[四行指标：标签和数值必须在同一行带上（100 + (i-1)*28），
    数值右对齐到卡片内边距；"12,480" 这种带千分位的数要留够 56px，
    否则会被 label 的裁剪区切掉尾巴。]]
    local rowtxt = { "入驻企业", "在岗人数", "今日访客", "车辆在园" }
    for i = 1, 4 do
        local y = 100 + (i - 1) * 28
        lbl(o.root, LY.kpi.x + 124, LY.kpi.y + y + 3, 52, 12, rowtxt[i], T.f.mini, C.dim, LB)
    end
    L.v1 = lbl(o.root, LY.kpi.x + 176, LY.kpi.y + 100, 56, 18, "", 14, C.txt, RA)
    L.v2 = lbl(o.root, LY.kpi.x + 176, LY.kpi.y + 128, 56, 18, "", 14, C.txt, RA)
    L.v3 = lbl(o.root, LY.kpi.x + 176, LY.kpi.y + 156, 56, 18, "", 14, C.txt, RA)
    L.v4 = lbl(o.root, LY.kpi.x + 176, LY.kpi.y + 184, 56, 18, "", 14, C.txt, RA)
    lbl(o.root, LY.kpi.x + 16, LY.kpi.y + 208, 90, 12, "月度目标达成", T.f.tiny, C.dim2, LB)
    L.target  = lbl(o.root, LY.kpi.x + 200, LY.kpi.y + 206, 32, 14, "", T.f.mini, C.teal, RA)

    -- 能耗监测
    lbl(o.root, LY.energy.x + 26, LY.energy.y + 12, 110, 18, "能耗监测", T.f.mid, C.txt, LB)
    lbl(o.root, LY.energy.x + 26, LY.energy.y + 30, 110, 12, "ENERGY", T.f.tiny, C.dim2, LB)
    L.today   = lbl(o.root, LY.energy.x + 120, LY.energy.y + 12, 96, 20, "", T.f.big, C.txt, RA)
    local ename = { "电", "水", "气" }
    for i = 1, 3 do
        local y = LY.energy.y + 64 + (i - 1) * 40
        lbl(o.root, LY.energy.x + 16, y, 28, 14, ename[i], T.f.small, C.dim, LB)
    end
    L.e1 = lbl(o.root, LY.energy.x + 176, LY.energy.y + 64, 44, 14, "", T.f.small, C.txt, RA)
    L.e2 = lbl(o.root, LY.energy.x + 176, LY.energy.y + 104, 44, 14, "", T.f.small, C.txt, RA)
    L.e3 = lbl(o.root, LY.energy.x + 176, LY.energy.y + 144, 44, 14, "", T.f.small, C.txt, RA)
    L.month   = lbl(o.root, LY.energy.x + 16, LY.energy.y + 190, 130, 14, "", T.f.small, C.dim, LB)
    L.yoy     = lbl(o.root, LY.energy.x + 136, LY.energy.y + 190, 80, 14, "", T.f.small, C.green, RA)

    -- 地图卡
    lbl(o.root, LY.map.x + 26, LY.map.y + 12, 150, 18, "园区实时态势", T.f.mid, C.txt, LB)
    lbl(o.root, LY.map.x + 26, LY.map.y + 30, 150, 12, "PARK MAP", T.f.tiny, C.dim2, LB)
    lbl(o.root, LY.map.x + 359, LY.map.y + 11, 26, 14, "警示", T.f.tiny, C.dim2, LB)
    lbl(o.root, LY.map.x + 399, LY.map.y + 11, 26, 14, "异常", T.f.tiny, C.dim2, LB)
    lbl(o.root, LY.map.x + 439, LY.map.y + 11, 26, 14, "提示", T.f.tiny, C.dim2, LB)
    -- 楼名放楼内左上角（而不是压在下边框上），字用 dim 色，远远能看清是哪一栋
    for _, b in ipairs(MP.buildings) do
        lbl(o.root,
            LY.map.x + 16 + b.x + 8,
            LY.map.y + 44 + b.y + 6,
            96, 14, b.name, T.f.mini, C.dim, LB)
    end
    -- 地图底部不再压文字：那块区域是宿舍区/物流门，叠字会糊在一起；
    -- "告警点位 3 / 在园车辆" 这两个信息在左卡和告警卡里已经有了。

    -- 服务小卡 1：通行
    lbl(o.root, LY.card1.x + 14, LY.card1.y + 10, 130, 14, "通行 · 车辆", T.f.body, C.txt, LB)
    lbl(o.root, LY.card1.x + 14, LY.card1.y + 32, 16, 14, "进", T.f.mini, C.dim2, LB)
    L.inflow  = lbl(o.root, LY.card1.x + 28, LY.card1.y + 27, 58, 18, "", 15, C.green, LB)
    lbl(o.root, LY.card1.x + 88, LY.card1.y + 31, 16, 14, "出", T.f.mini, C.dim2, LB)
    L.outflow = lbl(o.root, LY.card1.x + 100, LY.card1.y + 27, 44, 18, "", 15, C.blue, LB)
    lbl(o.root, LY.card1.x + 14, LY.card1.y + 60, 50, 12, "人工放行", T.f.mini, C.dim, LB)
    lbl(o.root, LY.card1.x + 14, LY.card1.y + 76, 50, 12, "ETC 通行", T.f.mini, C.dim, LB)
    lbl(o.root, LY.card1.x + 14, LY.card1.y + 92, 50, 12, "临停入场", T.f.mini, C.dim, LB)
    L.manual  = lbl(o.root, LY.card1.x + 104, LY.card1.y + 60, 40, 12, "", T.f.small, C.txt, RA)
    L.etc     = lbl(o.root, LY.card1.x + 104, LY.card1.y + 76, 40, 12, "", T.f.small, C.txt, RA)
    L.tempc   = lbl(o.root, LY.card1.x + 104, LY.card1.y + 92, 40, 12, "", T.f.small, C.txt, RA)

    -- 服务小卡 2：环境
    lbl(o.root, LY.card2.x + 14, LY.card2.y + 10, 130, 14, "环境 · 空气", T.f.body, C.txt, LB)
    L.pm25  = lbl(o.root, LY.card2.x + 14, LY.card2.y + 28, 40, 20, "", T.f.big, C.teal, LB)
    L.pmq   = lbl(o.root, LY.card2.x + 54, LY.card2.y + 32, 70, 14, "", T.f.mini, C.green, LB)
    lbl(o.root, LY.card2.x + 14, LY.card2.y + 60, 50, 12, "噪声", T.f.mini, C.dim, LB)
    lbl(o.root, LY.card2.x + 14, LY.card2.y + 76, 50, 12, "温度", T.f.mini, C.dim, LB)
    lbl(o.root, LY.card2.x + 14, LY.card2.y + 92, 50, 12, "湿度", T.f.mini, C.dim, LB)
    L.noise = lbl(o.root, LY.card2.x + 92, LY.card2.y + 60, 52, 12, "", T.f.small, C.txt, RA)
    L.temp  = lbl(o.root, LY.card2.x + 92, LY.card2.y + 76, 52, 12, "", T.f.small, C.txt, RA)
    L.hum   = lbl(o.root, LY.card2.x + 92, LY.card2.y + 92, 52, 12, "", T.f.small, C.txt, RA)

    -- 服务小卡 3：工单
    lbl(o.root, LY.card3.x + 14, LY.card3.y + 10, 130, 14, "服务 · 工单", T.f.body, C.txt, LB)
    L.todo  = lbl(o.root, LY.card3.x + 14, LY.card3.y + 28, 30, 20, "", T.f.big, C.amber, LB)
    lbl(o.root, LY.card3.x + 44, LY.card3.y + 32, 50, 14, "待处理", T.f.mini, C.dim, LB)
    lbl(o.root, LY.card3.x + 14, LY.card3.y + 60, 60, 12, "处理中", T.f.mini, C.dim, LB)
    lbl(o.root, LY.card3.x + 14, LY.card3.y + 76, 60, 12, "今日完成", T.f.mini, C.dim, LB)
    L.doing = lbl(o.root, LY.card3.x + 104, LY.card3.y + 60, 40, 12, "", T.f.small, C.txt, RA)
    L.done  = lbl(o.root, LY.card3.x + 104, LY.card3.y + 76, 40, 12, "", T.f.small, C.txt, RA)

    -- 实时告警
    lbl(o.root, LY.alarm.x + 26, LY.alarm.y + 12, 100, 18, "实时告警", T.f.mid, C.txt, LB)
    lbl(o.root, LY.alarm.x + 26, LY.alarm.y + 30, 100, 12, "ALARM", T.f.tiny, C.dim2, LB)
    L.al_cnt = lbl(o.root, LY.alarm.x + 140, LY.alarm.y + 12, 76, 14, "", T.f.small, C.red, RA)
    for i = 1, 5 do
        local y = LY.alarm.y + 50 + (i - 1) * 32
        o.al_row[i] = {
            t = lbl(o.root, LY.alarm.x + 24, y, 34, 12, "", T.f.tiny, C.dim2, LB),
            p = lbl(o.root, LY.alarm.x + 60, y, 76, 12, "", T.f.mini, C.dim, LB),
            x = lbl(o.root, LY.alarm.x + 24, y + 14, 196, 12, "", T.f.mini, C.txt, LB),
        }
    end
    lbl(o.root, LY.alarm.x + 16, LY.alarm.y + 212, 90, 14, "查看全部 >", T.f.mini, C.accent, LB)

    -- 安防与通行
    lbl(o.root, LY.secu.x + 26, LY.secu.y + 12, 110, 18, "安防与通行", T.f.mid, C.txt, LB)
    lbl(o.root, LY.secu.x + 26, LY.secu.y + 30, 110, 12, "SECURITY", T.f.tiny, C.dim2, LB)
    lbl(o.root, LY.secu.x + 16, LY.secu.y + 52, 60, 14, "设备在线率", T.f.mini, C.dim, LB)
    L.sec_rate = lbl(o.root, LY.secu.x + 140, LY.secu.y + 46, 76, 20, "", T.f.big, C.green, RA)
    local sname = { "视频监控", "门禁通道", "消防设备", "广播系统" }
    for i = 1, 4 do
        local y = LY.secu.y + 96 + (i - 1) * 24
        lbl(o.root, LY.secu.x + 30, y, 70, 14, sname[i], T.f.mini, C.dim, LB)
        o.sec[i].lb = lbl(o.root, LY.secu.x + 140, y, 76, 14, "", T.f.small, C.txt, RA)
    end
    L.pass = lbl(o.root, LY.secu.x + 16, LY.secu.y + 190, 160, 14, "", T.f.small, C.dim, LB)

    -- 底栏
    L.notice = lbl(o.root, 36, LY.bottom_y + 8, 680, 18, "", T.f.body, C.dim, LB)
    lbl(o.root, 720, LY.bottom_y + 12, 280, 14, "数据每 2 秒刷新 · 386 台设备在线",
        T.f.tiny, C.dim2, RA)

    -- 首屏铺一次
    step_data(0)
    draw_kpi(); draw_energy(); draw_alarm(); draw_secu(); draw_svc2(); draw_svc3()
    for i = 1, #o.pins do draw_pin(i) end
    set_hl(1)
    sync_texts()
    sync_clock()
    log.info("park", "界面构建完成")
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
    local waitMs = T.perf.frame_ms

    while true do
        sys.wait(waitMs)

        local now = read_tick()
        local rawMs
        if now and prev then
            rawMs = tick_ms(tick_delta(now, prev))
            prev = now
            if rawMs > 250 then rawMs = 250 end
            if rawMs < 0 then rawMs = 0 end
        else
            rawMs = T.perf.frame_ms
        end
        accMs = accMs + rawMs
        accN = accN + 1
        if accN >= avgN then
            dtMs = accMs / accN
            accMs, accN = 0, 0
        end
        local dt = dtMs / 1000
        if dt > 0.2 then dt = 0.2 elseif dt < 0.004 then dt = 0.004 end

        t = t + dt
        o.t = t

        step_data(t)

        -- 告警点位脉冲：每帧只有三个 44x44 的小块
        for i = 1, #o.pins do draw_pin(i) end

        -- 卡片轮转：一次只重画一张
        cardT = cardT + dt
        if cardT >= T.perf.card_ms / 1000 then
            cardT = 0
            o.card_i = o.card_i % #CARD_FN + 1
            local ok, err = pcall(CARD_FN[o.card_i])
            if not ok then log.error("park", "卡片刷新异常", err) end
        end

        -- 文本：值变了才写
        textT = textT + dt
        if textT >= T.perf.text_ms / 1000 then
            textT = 0
            local ok, err = pcall(sync_texts)
            if not ok then log.error("park", "文本刷新异常", err) end
        end

        -- 时钟
        clockT = clockT + dt
        if clockT >= 1 then
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

        -- 建筑巡览高亮
        hlT = hlT + dt
        if hlT >= T.perf.hl_ms / 1000 then
            hlT = 0
            local n = #MP.buildings
            o.hl = o.hl or 0
            set_hl(o.hl % n + 1)
        end
    end
end

return M
