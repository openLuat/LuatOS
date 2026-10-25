--[[
@module  view_twin
@summary 视图1 孪生总览：3D 车间底图 + 全息地面层 + 三处设备热点 + 六张玻璃面板
@version 1.0
@date    2026.10.23
@author  江访

=== 这一页在讲什么 ===
"现在车间长什么样"：中央是车间三维实景（AI 渲染图，一比一贴，不缩放不动），
地面层以上叠的全息网格 / 光柱 / 流光全部按透视相机实时算（scene3d），
三处设备热点把"图上的机器"和"面板里的数"连起来。

=== 为什么地面层不用裁剪画布 ===
中央场景区是 x 290..734，而地面网格的张角随 z 变化（近处宽、远处窄）。
只要把世界 x 范围卡在 ±1.45，三个关键深度上的投影都落在 300..724 之内：
    z=-4.6 -> x 318..706      z=-4.0 -> x 300..724      z=-0.7 -> x 374..650
于是整页只需要一个全屏 shape，网格也不会横穿玻璃面板。
（如果以后把网格加宽，就必须改成挂在舞台容器下的第二个画布。）
]]

local T  = require "theme"
local B  = require "bdui"
local S  = require "scene3d"

local c = T.c
local f = T.f
local CL, CR = T.cardL, T.cardR

local M = { id = "twin", name = "孪生总览" }

-- ==================== 热点（世界坐标 + 标签屏幕坐标）====================
--[[
x/z 是地面世界坐标，交给 scene3d 算屏幕点；
tx/ty 是标签左上角（屏幕坐标）——标签是静态对象，只有数值在变，
位置可以写死，不用每帧 set_pos（每次 set_pos 都会 invalidate 一块矩形）。
]]
local HOT = {
    { tag = "SMT-A", x = -1.05, z = -3.50, tx = 384, ty = 352, w = 104 },
    { tag = "ASM-1", x = 0.05,  z = -2.30, tx = 526, ty = 272, w = 110 },
    { tag = "PKG-1", x = 1.15,  z = -3.10, tx = 632, ty = 322, w = 100 },
}

-- 地面光路：把三个热点串成一条物料流（世界坐标折线）
local PATH_X = { -1.05, -0.62, -0.15, 0.05, 0.48, 0.90, 1.15 }
local PATH_Z = { -3.50, -2.95, -2.52, -2.30, -2.62, -2.92, -3.10 }

-- ==================== 构建 ====================
function M.build(parent, data)
    local o = { data = data, tx = {}, hot = false }

    -- ---------- 1. 卡片容器 ----------
    o.cL1 = B.card(parent, CL[1], c.cyan)
    o.cL2 = B.card(parent, CL[2], c.teal)
    o.cL3 = B.card(parent, CL[3], c.violet)
    o.cR1 = B.card(parent, CR[1], c.amber)
    o.cR2 = B.card(parent, CR[2], c.cyan)
    o.cR3 = B.card(parent, CR[3], c.red)

    --[[---------- 2. 图片：一个都不用（真机内存约束）----------
    OEE 卡里的全息环本来是 res/holo_ring.png（256x256 ARGB8888 = 262KB 连续内存），
    光柱是两个 res/holo_beam.png。真机上这类图属于"能解码成功、但随时可能因为
    内存碎片失败"的灰色地带；一旦失败，LVGL 每次重绘都会重新解码（369ms/次），
    帧率直接塌到 1~2fps。
    现在环改成纯矢量弧（见 update 里 draw_holo_ring），光柱本来就是 scene3d 画的，
    贴图只是加强氛围——去掉后整屏零 PNG 依赖。]]

    -- ---------- 3. 画布 ----------
    o.shape = airui.shape({
        parent = parent, x = 0, y = 0,
        w = T.screen.w, h = T.screen.h, items = {},
    })

    -- ---------- 4. 文字 ----------
    -- 左1 OEE（环图片 + 中心大数）
    B.head(o.cL1, "综合效率 OEE", CL[1].w, c.dim)
    o.oee   = B.text(o.cL1, 6, 80, 128, 46, f.big, c.txt, airui.TEXT_ALIGN_CENTER, "87.4")
    o.m1    = B.text(o.cL1, 150, 44, 110, 18, f.sub, c.dim, airui.TEXT_ALIGN_LEFT, "")
    o.m2    = B.text(o.cL1, 150, 72, 110, 18, f.sub, c.dim, airui.TEXT_ALIGN_LEFT, "")
    o.m3    = B.text(o.cL1, 150, 100, 110, 18, f.sub, c.dim, airui.TEXT_ALIGN_LEFT, "")
    o.m4    = B.text(o.cL1, 150, 132, 116, 24, f.text, c.cyan, airui.TEXT_ALIGN_LEFT, "")

    -- 左2 产量
    B.head(o.cL2, "今日产量", CL[2].w, c.dim)
    o.out   = B.text(o.cL2, 12, 30, 160, 46, f.big, c.txt, airui.TEXT_ALIGN_LEFT, "1284")
    o.outU  = B.text(o.cL2, 134, 54, 42, 18, f.mini, c.teal, airui.TEXT_ALIGN_LEFT, "pcs")
    o.plan  = B.text(o.cL2, 176, 34, 84, 18, f.mini, c.dim, airui.TEXT_ALIGN_RIGHT, "")
    o.rate  = B.text(o.cL2, 176, 56, 84, 18, f.mini, c.amber, airui.TEXT_ALIGN_RIGHT, "")

    -- 左3 设备（3 列 x 2 行）
    o.devTitle = B.head(o.cL3, "设备在线", CL[3].w, c.dim)
    o.devTag, o.devSt = {}, {}
    --[[设备格坐标必须和 update() 里的灯 / 健康条共用一个基准
    早先文字用 36 起、图元用 34 起，差 2px 看着没事，
    实际上灯落在了两行文字的缝里，肉眼会把灯配到下一台设备上（状态色和文字对不上）。]]
    for i = 1, data.NDEV do
        local col = (i - 1) % 3
        local row = (i - 1) // 3
        local x = 10 + col * 86
        local y = 34 + row * 40
        o.devTag[i] = B.text(o.cL3, x + 16, y, 62, 18, f.sub, c.txt, airui.TEXT_ALIGN_LEFT, "")
        o.devSt[i]  = B.text(o.cL3, x + 16, y + 18, 62, 16, f.mini, c.dim, airui.TEXT_ALIGN_LEFT, "")
    end

    -- 右1 能耗
    B.head(o.cR1, "实时功率", CR[1].w, c.dim)
    o.pow   = B.text(o.cR1, 12, 30, 140, 46, f.big, c.txt, airui.TEXT_ALIGN_LEFT, "386")
    o.powU  = B.text(o.cR1, 134, 54, 42, 18, f.mini, c.amber, airui.TEXT_ALIGN_LEFT, "kW")
    o.peak  = B.text(o.cR1, 168, 34, 92, 18, f.mini, c.dim, airui.TEXT_ALIGN_RIGHT, "")
    o.unit  = B.text(o.cR1, 12, 72, 140, 18, f.mini, c.dim2, airui.TEXT_ALIGN_LEFT, "")

    -- 右2 工况（两个 240 度表）
    B.head(o.cR2, "关键工况", CR[2].w, c.dim)
    o.tLab = B.text(o.cR2, 20, 34, 100, 18, f.mini, c.dim, airui.TEXT_ALIGN_CENTER, "主轴温度")
    o.vLab = B.text(o.cR2, 152, 34, 100, 18, f.mini, c.dim, airui.TEXT_ALIGN_CENTER, "轴承振动")
    o.tVal = B.text(o.cR2, 20, 122, 100, 22, f.text, c.amber, airui.TEXT_ALIGN_CENTER, "")
    o.vVal = B.text(o.cR2, 152, 122, 100, 22, f.text, c.cyan, airui.TEXT_ALIGN_CENTER, "")

    -- 右3 告警
    B.head(o.cR3, "实时告警", CR[3].w, c.dim)
    o.alarmTxt, o.alarmT = {}, {}
    for i = 1, data.NALARM do
        o.alarmTxt[i] = B.text(o.cR3, 20, 34 + (i - 1) * 29, 190, 18, f.sub, c.txt, airui.TEXT_ALIGN_LEFT, "")
        o.alarmT[i]   = B.text(o.cR3, 212, 34 + (i - 1) * 29, 48, 18, f.mini, c.dim2, airui.TEXT_ALIGN_RIGHT, "")
    end

    -- 热点标签
    o.tag1, o.tag2 = {}, {}
    for i = 1, #HOT do
        local h = HOT[i]
        local box = airui.container({
            parent = parent, x = h.tx, y = h.ty, w = h.w, h = 38,
            color = 0x06121E, color_opacity = 205, radius = 4,
            border_color = 0x1D4E6E, border_width = 1,
        })
        o.tag1[i] = airui.label({
            parent = box, x = 7, y = 2, w = h.w - 12, h = 18,
            text = h.tag, font_size = f.sub, color = c.cyan,
            align = airui.TEXT_ALIGN_LEFT,
        })
        o.tag2[i] = airui.label({
            parent = box, x = 7, y = 19, w = h.w - 12, h = 16,
            text = "", font_size = f.mini, color = c.dim,
            align = airui.TEXT_ALIGN_LEFT,
        })
    end

    -- 预建采样缓冲（每帧新建表会喂 GC）
    o.bufProd, o.bufPow = {}, {}
    return o
end

--[[OEE 全息环（纯矢量，替代 res/holo_ring.png）
三道同心弧 + 四个正交刻度：外圈 270° 主环（开口朝下，仪表盘的经典缺口）、
外侧一段缓慢旋转的短弧（暗示"在转"）、内圈一段参考弧。
半径 48 的进度圈仍由 B.gauge 画点串，两者叠起来就是原来那张图的质感，
但图元只有 28 个、零解码、零内存。]]
local function draw_holo_ring(P, cx, cy, r, color, t)
    P:arc(cx, cy, r, math.pi * 0.75, math.pi * 2.25, 18, color, 1, 60, false, false)

    local a0 = -t * 0.6
    P:arc(cx, cy, r + 6, a0, a0 + math.pi * 0.5, 6, c.violet, 1, 130, false, false)

    P:arc(cx, cy, r - 13, math.pi * 0.9, math.pi * 2.1, 6, c.dim2, 1, 90, false, false)

    for k = 0, 3 do
        local a = k * math.pi * 0.5
        local co, si = math.cos(a), math.sin(a)
        P:line(cx + co * (r + 3), cy + si * (r + 3),
               cx + co * (r + 9), cy + si * (r + 9), color, 1, 110)
    end
end

-- ==================== 每帧更新 ====================
function M.update(o, P, t, dt)
    local d = o.data
    B.hot(o, dt)

    -- ---------------- 面板 ----------------
    B.brackets(P, CL[1], c.cyan, 130)
    B.brackets(P, CR[1], c.amber, 130)
    B.brackets(P, CR[3], c.red, 110)

    -- OEE：矢量全息环 + 进度点串
    draw_holo_ring(P, CL[1].x + 70, CL[1].y + 98, 48, c.cyan, t)
    B.gauge(P, CL[1].x + 70, CL[1].y + 98, 48, d.kpi.oee, c.cyan,
        -math.pi / 2, -math.pi / 2 + math.pi * 2, 5, 20)

    -- 工况两个 240 度表（圆心略上移，给底部读数留位置）
    B.gauge(P, CR[2].x + 72, CR[2].y + 86, 30, d.raw.temp / 70, c.amber, 0.6, 4.8, 5, 12)
    B.gauge(P, CR[2].x + 204, CR[2].y + 86, 30, d.raw.vib / 10, c.cyan, 0.6, 4.8, 5, 12)

    -- 迷你趋势
    B.spark(P, d.sample(d.series.prod, 16, o.bufProd), 16,
        CL[2].x + 12, CL[2].y + 98, 248, 34, c.teal, 1, 200)
    B.spark(P, d.sample(d.series.power, 16, o.bufPow), 16,
        CR[1].x + 12, CR[1].y + 94, 248, 34, c.amber, 1, 190)

    -- 设备格：呼吸状态灯 + 健康度细条
    for i = 1, d.NDEV do
        local dv = d.devs[i]
        local col = (i - 1) % 3
        local row = (i - 1) // 3
        local x = CL[3].x + 10 + col * 86
        local y = CL[3].y + 34 + row * 40
        local scon = B.STATE_COL[dv.state]
        local br = 4 + 1.6 * (0.5 + 0.5 * math.sin(t * 2.2 + dv.phase))
        P:dot(x + 7, y + 9, math.floor(br * 2.4), scon, 45)
        P:dot(x + 7, y + 9, math.floor(br), scon, 235)
        -- 健康度细条：只做"底色提示"，不能画成下划线（会像删除线）
        P:box(x + 17, y + 36, 44, 2, 0x0F2236, 200, 1)
        P:box(x + 17, y + 36, 44 * dv.health, 2, scon, 150, 1)
    end

    -- 告警等级色条（level 3 呼吸）
    for i = 1, d.NALARM do
        local a = d.alarms[i]
        local y = CR[3].y + 32 + (i - 1) * 29
        local opa = 200
        if a.level == 3 then
            opa = 150 + 105 * (0.5 + 0.5 * math.sin(t * 3.4))
        end
        P:box(CR[3].x + 12, y, 3, 16, B.LEVEL_COL[a.level], opa, 1)
    end

    -- ---------------- 地面全息层 ----------------
    -- 场景视口取景框：让"实景底图"看起来是一块独立的 3D 视口，而不是整屏壁纸
    B.brackets4(P, { x = T.stage.x, y = T.stage.y + 6, w = T.stage.w, h = T.stage.h - 14 },
        c.cyan, 90, 18)

    S.grid(P, t, T.ground.x0, T.ground.x1, T.ground.z0, T.ground.z1, T.ground.step,
        c.grid, c.cyan)

    S.flow(P, PATH_X, PATH_Z, #PATH_X, t, c.teal, 1.5, 4, 100)

    -- 光柱：远 -> 近，近的压住远的
    local order = { 2, 1, 3 }
    for n = 1, #order do
        local i = order[n]
        local h, dv = HOT[i], d.devs[i]
        S.pillar(P, h.x, h.z, 0.62, dv.health, B.STATE_COL[dv.state], t, n * 1.3)
    end

    -- 热点 -> 标签的引导线
    for i = 1, #HOT do
        local h = HOT[i]
        local px, py = S.at(h.x, 0.62, h.z)
        local tx = (i == 2) and (h.tx + h.w) or h.tx
        P:line(px, py, tx, h.ty + 12, c.cyan, 1, 80)
        P:dot(px, py, 2, c.cyan, 210)
    end

    -- ---------------- 文字（5Hz）----------------
    if o.hot then
        B.put(o.oee, string.format("%.1f", d.kpi.oee * 100), o, "oee")
        B.put(o.m1, string.format("达成  %d%%", math.floor(d.kpi.oee * 106)), o, "m1")
        B.put(o.m2, string.format("停机  %dmin", 12 + math.floor(t) % 9), o, "m2")
        B.put(o.m3, string.format("节拍  %.1fs", d.kpi.cycle), o, "m3")
        B.put(o.m4, string.format("%d pcs/h", math.floor(d.raw.prod)), o, "m4")


        B.put(o.out, string.format("%d", math.floor(d.kpi.output)), o, "out")
        B.put(o.plan, string.format("计划 %d", d.kpi.plan), o, "plan")
        B.put(o.rate, string.format("达成 %d%%",
            math.floor(d.kpi.output / d.kpi.plan * 100)), o, "rate")

        B.put(o.devTitle, string.format("设备在线 %d/%d", d.kpi.online, d.kpi.total), o, "devT")
        for i = 1, d.NDEV do
            local dv = d.devs[i]
            B.put(o.devTag[i], dv.tag, o, "dt" .. i)
            B.put(o.devSt[i], B.STATE_TXT[dv.state], o, "ds" .. i)
            o.devSt[i]:set_color(B.STATE_COL[dv.state])
        end

        B.put(o.pow, string.format("%d", math.floor(d.raw.power)), o, "pow")
        B.put(o.peak, string.format("峰值 %d kW", d.kpi.peak), o, "peak")
        B.put(o.unit, string.format("%.2f kWh/pcs", d.raw.unit), o, "unit")

        B.put(o.tVal, string.format("%.1f C", d.raw.temp), o, "tv")
        B.put(o.vVal, string.format("%.1f mm/s", d.raw.vib), o, "vv")

        for i = 1, d.NALARM do
            local a = d.alarms[i]
            B.put(o.alarmTxt[i], a.text, o, "at" .. i)
            B.put(o.alarmT[i], string.format("%d s", math.floor(a.t)), o, "an" .. i)
        end

        for i = 1, #HOT do
            local dv = d.devs[i]
            B.put(o.tag2[i], string.format("%s  负载 %d%%", B.STATE_TXT[dv.state],
                math.floor(dv.load * 100)), o, "tg" .. i)
        end
    end
end

return M
