--[[
@module  ui_overview
@summary 总览页：环形真空室动画 + KPI + 放电时序 + 子系统 + 磁约束 + 事件流
@version 1.0
@date    2026.11.12
@note    内容区坐标原点在 (0,0)，实际屏幕 y 需 +56（顶部栏高度）
]]
local theme = require "theme"
local art   = require "art"
local sim   = require "sim"
local conf  = require "conf"

local C = theme.C
local SZ = theme.SZ
local A_LEFT, A_CENTER, A_RIGHT = theme.align_left(), theme.align_center(), theme.align_right()

local M = {}

-- 布局常量（内容区 1024x544）
local L = {
    hero    = { x = 14,  y = 10,  w = 610, h = 318 },
    kpi     = { x = 14,  y = 340, w = 610, h = 96 },
    phase   = { x = 14,  y = 448, w = 610, h = 86 },
    devices = { x = 636, y = 10,  w = 374, h = 162 },
    magnetic = { x = 636, y = 184, w = 374, h = 148 },
    events  = { x = 636, y = 344, w = 374, h = 190 },
}

local TORUS = { cx = 198, cy = 170, R = 84, rt = 30, squash = 0.62 }

-- ===================== 页面 =====================
function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 真空室动画 ====================
    local hero = theme.card(root, L.hero.x, L.hero.y, L.hero.w, L.hero.h, { radius = 14 })

    theme.label(hero, 16, 10, 260, 18, "环形真空室，3/4 视图", SZ.s, C.ink)
    theme.label(hero, 16, 29, 300, 16,
        string.format("R0 %.2f m / a %.2f m / Bt %.2f T",
            conf.machine.R0, conf.machine.a, conf.machine.Bt), SZ.xs, C.ink3)

    local chip = theme.chip(hero, 512, 12, 82, 22, "待机", C.bg0, C.ink3, SZ.xs)

    local torus = art.torus(hero, TORUS.cx, TORUS.cy, TORUS.R, TORUS.rt, TORUS.squash, {
        plasma_hi = C.plasma, plasma_lo = C.coral,
        w = L.hero.w, h = L.hero.h,
    })
    page.torus = torus

    theme.label(hero, 16, 286, 200, 14, "环向场线圈 ×16 / 钨偏滤器", SZ.xs, C.ink3)
    theme.label(hero, 214, 286, 176, 14, "中心螺线管 CS / 4.5 K", SZ.xs, C.ink3, A_RIGHT)

    -- 右侧读数
    theme.label(hero, 336, 18, 160, 16, "等离子体电流", SZ.xs, C.ink3)
    local ip_val = theme.label(hero, 334, 30, 150, 48, "0.00", SZ.hero, C.ink)
    theme.label(hero, 476, 54, 40, 16, "MA", SZ.s, C.ink2)
    theme.hline(hero, 336, 84, 258, C.line)

    local rows = {}
    local ROW_DEF = {
        { key = "te",   cap = "电子温度", unit = "keV", color = C.coral, max = 10 },
        { key = "ne",   cap = "电子密度 / 10^19 m^-3", unit = "", color = C.ion, max = 5 },
        { key = "pfus", cap = "聚变功率", unit = "MW", color = C.plasma, max = 80 },
    }
    for i, d in ipairs(ROW_DEF) do
        local y = 94 + (i - 1) * 44
        theme.label(hero, 336, y, 180, 16, d.cap, SZ.xs, C.ink3)
        local val = theme.label(hero, 336, y + 15, 120, 18, "--", SZ.m, C.ink)
        local unit = theme.label(hero, 448, y + 17, 60, 14, d.unit, SZ.xs, C.ink3)
        local bar = theme.bar(hero, 512, y + 19, 82, 4, 0, d.color, C.panel3)
        rows[i] = { def = d, val = val, bar = bar }
    end
    page.rows = rows

    local q_chip = theme.chip(hero, 336, 232, 76, 22, "Q 0.00", C.bg0, C.panel3, SZ.xs)
    local h_chip = theme.chip(hero, 420, 232, 86, 22, "H98 1.00", C.ion, C.panel3, SZ.xs)
    local mode_chip = theme.chip(hero, 514, 232, 80, 22, "L 模", C.ink2, C.panel2, SZ.xs)
    page.q_chip = q_chip
    page.h_chip = h_chip
    page.mode_chip = mode_chip

    -- 真空室状态行
    theme.hline(hero, 336, 264, 258, C.line)
    local plasma_state = theme.label(hero, 336, 270, 258, 16, "等离子体未建立", SZ.xs, C.ink3)
    page.plasma_state = plasma_state

    -- ==================== KPI ====================
    local kpi = theme.card(root, L.kpi.x, L.kpi.y, L.kpi.w, L.kpi.h, { radius = 14 })
    local KPI_DEF = {
        { key = "bt",     cap = "环向磁场", unit = "T" },
        { key = "energy", cap = "等离子体储能", unit = "MJ" },
        { key = "q",      cap = "能量增益", unit = "Q" },
        { key = "h98",    cap = "约束因子", unit = "H98" },
    }
    local kpis = {}
    local cell_w = math.floor(L.kpi.w / 4)
    for i, d in ipairs(KPI_DEF) do
        local x = (i - 1) * cell_w
        if i > 1 then theme.vline(kpi, x, 14, L.kpi.h - 28, C.line) end
        theme.label(kpi, x + 16, 10, cell_w - 24, 16, d.cap, SZ.xs, C.ink3)
        local val = theme.label(kpi, x + 16, 28, cell_w - 24, 42, "--", SZ.xl, C.ink)
        theme.label(kpi, x + 16, 72, cell_w - 24, 14, d.unit, SZ.xs, C.ink3)
        kpis[i] = { def = d, val = val }
    end
    page.kpis = kpis

    -- ==================== 放电时序 ====================
    local ph = theme.card(root, L.phase.x, L.phase.y, L.phase.w, L.phase.h, { radius = 14 })
    theme.label(ph, 14, 8, 90, 18, "放电时序", SZ.s, C.ink)
    local ph_shot = theme.label(ph, 78, 10, 220, 16, "", SZ.xs, C.ink3)
    local ph_time = theme.label(ph, 300, 8, 110, 16, "T+ 0 s", SZ.xs, C.ink2, A_RIGHT)

    local btn_start = theme.button(ph, 470, 5, 60, 22, "启动", {
        bg = C.plasma, size = SZ.xs,
        on_click = function()
            sim.start_shot()
            page.refresh(true)
        end,
    })
    local btn_abort = theme.ghost(ph, 538, 5, 58, 22, "终止", {
        size = SZ.xs,
        on_click = function()
            if sim.abort() then
                page.refresh(true)
            end
        end,
    })
    page.btn_start = btn_start
    page.btn_abort = btn_abort

    local total_dur = 0
    for _, p in ipairs(conf.phases) do total_dur = total_dur + p.dur end
    local avail_w = L.phase.w - 28
    local segs = {}
    local sx = 14
    for i, p in ipairs(conf.phases) do
        local w = math.floor(avail_w * p.dur / total_dur) - 3
        local bar = theme.bar(ph, sx, 36, w, 6, 0, p.color, C.panel3, 3)
        local lb = theme.label(ph, sx - 2, 46, w + 4, 14, p.short, SZ.xs, C.ink3, A_CENTER)
        segs[i] = { bar = bar, label = lb, def = p, w = w }
        sx = sx + w + 3
    end
    page.segs = segs
    page.ph_shot = ph_shot
    page.ph_time = ph_time

    -- ==================== 子系统 ====================
    local dc = theme.card(root, L.devices.x, L.devices.y, L.devices.w, L.devices.h, { radius = 14 })
    theme.label(dc, 14, 8, 160, 18, "子系统", SZ.s, C.ink)
    local dev_count = theme.label(dc, 220, 8, 140, 18, "", SZ.xs, C.ink3, A_RIGHT)

    local tiles = {}
    for i, d in ipairs(conf.subsystems) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local tw, th = 170, 28
        local x = 14 + col * (tw + 6)
        local y = 32 + row * (th + 4)
        local box = theme.box(dc, x, y, tw, th, C.panel2, 8)
        art.icon(dc, d.icon, x + 8, y + 7, 14, C.ink2)
        theme.label(dc, x + 28, y + 6, 96, 16, d.name, SZ.s, C.ink)
        local st = theme.label(dc, x + 108, y + 7, 52, 14, "", SZ.xs, C.ink3, A_RIGHT)
        local dot = theme.box(dc, x + tw - 10, y + 11, 5, 5, C.green, 3)
        box:set_on_click(function()
            sim.toggle_device(d.key)
            page.refresh(true)
        end)
        tiles[i] = { box = box, st = st, dot = dot, def = d }
    end
    page.tiles = tiles
    page.dev_count = dev_count

    -- ==================== 磁约束摘要 ====================
    local mc = theme.card(root, L.magnetic.x, L.magnetic.y, L.magnetic.w, L.magnetic.h, { radius = 14 })
    theme.label(mc, 14, 8, 160, 18, "磁约束", SZ.s, C.ink)
    local mc_mode = theme.label(mc, 220, 8, 140, 18, "", SZ.xs, C.ink3, A_RIGHT)

    local MP = {
        { key = "kappa", cap = "拉长比 κ" },
        { key = "delta", cap = "三角形变 δ" },
        { key = "q95",   cap = "安全因子 q95" },
        { key = "beta",  cap = "归一化比压 βN" },
    }
    local mvals = {}
    for i, d in ipairs(MP) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 14 + col * 176
        local y = 34 + row * 38
        theme.label(mc, x, y, 160, 14, d.cap, SZ.xs, C.ink3)
        mvals[i] = theme.label(mc, x, y + 15, 160, 18, "--", SZ.m, C.ink)
    end
    page.mvals = mvals

    theme.hline(mc, 14, 110, 346, C.line)
    local risk_cap = theme.label(mc, 14, 118, 120, 16, "破裂风险", SZ.xs, C.ink3)
    local risk_val = theme.label(mc, 250, 118, 110, 16, "--", SZ.xs, C.ink, A_RIGHT)
    local risk_bar = theme.bar(mc, 14, 136, 346, 4, 0, C.green, C.panel3)
    page.risk_cap = risk_cap
    page.risk_val = risk_val
    page.risk_bar = risk_bar
    page.mc_mode = mc_mode

    -- ==================== 事件 ====================
    local ec = theme.card(root, L.events.x, L.events.y, L.events.w, L.events.h, { radius = 14 })
    theme.label(ec, 14, 8, 160, 18, "运行事件", SZ.s, C.ink)
    local ec_more = theme.label(ec, 220, 8, 140, 18, "", SZ.xs, C.ink3, A_RIGHT)
    local erows = {}
    for i = 1, 5 do
        local y = 32 + (i - 1) * 30
        local dot = theme.box(ec, 14, y + 7, 5, 5, C.green, 3)
        local t = theme.label(ec, 26, y + 1, 42, 14, "", SZ.xs, C.ink3)
        local tx = theme.label(ec, 72, y + 1, 288, 16, "", SZ.xs, C.ink2)
        local tx2 = theme.label(ec, 72, y + 15, 288, 12, "", SZ.xs, C.ink3)
        erows[i] = { dot = dot, time = t, text = tx, sub = tx2 }
    end
    page.event_rows = erows
    page.event_more = ec_more

    -- ==================== 刷新 ====================
    --[[
    总览页每秒要刷新的字段接近 70 个。逐条 set_text 会让 LVGL 反复重排文本、
    重绘脏区，单帧很容易超过 110 ms 的采样周期，把 SoC 的静态事件池顶满
    （日志 soc_send_event_to_task ... no free static event）。
    这里做三层降载：
      1、值不变不写：文本、颜色、进度条分别缓存
      2、前半（真空室读数 + 时序）每秒刷，后半（KPI/子系统/磁约束/事件）隔秒刷；
         首屏与按钮操作用 force 全量刷
      3、事件列表按“最新事件签名”跳过，没有新事件就不动 20 个标签
    ]]
    local tcache, ccache, bcache = {}, {}, {}
    local function st(lb, txt)
        if tcache[lb] ~= txt then
            tcache[lb] = txt
            lb:set_text(txt)
        end
    end
    local function sc(lb, col)
        if ccache[lb] ~= col then
            ccache[lb] = col
            lb:set_color(col)
        end
    end
    local function sb(bar, v)
        if not bar then return end
        v = theme.n(v)
        if bcache[bar] ~= v then
            bcache[bar] = v
            theme.setbar(bar, v)
        end
    end

    local round = 0
    local ev_sig = ""
    local btn_sig = ""

    local function refresh(force)
        if not page.alive then return end
        round = round + 1
        local s = sim.summary()
        local p = sim.phase()
        local front = true
        local back = force or (round % 2 == 0)

        -- ===== 前半：真空室读数 + 放电时序（变化最快，保持 1 秒）=====
        if front then
            st(ip_val, string.format("%.2f", s.ip))
            sc(ip_val, s.ip > 0.05 and C.ink or C.ink3)

            local vals = {
                { string.format("%.2f", s.te), math.min(100, s.te / 10 * 100) },
                { string.format("%.2f", s.ne), math.min(100, s.ne / 5 * 100) },
                { string.format("%.1f", s.pfus), math.min(100, s.pfus / 80 * 100) },
            }
            for i, r in ipairs(page.rows) do
                st(r.val, vals[i][1])
                sc(r.val, s.ip > 0.05 and C.ink or C.ink3)
                sb(r.bar, vals[i][2])
            end

            page.q_chip.set(string.format("Q %.2f", s.q), s.q > 1 and C.green or C.ink2)
            page.h_chip.set(string.format("H98 %.2f", s.h98), s.h98 > 1.0 and C.ion or C.ink2)
            page.mode_chip.set(s.q > 1 and "H 模" or (s.ip > 0.1 and "L 模" or "无等离子体"),
                s.q > 1 and C.green or C.ink3)

            local state_text
            if s.ip < 0.05 then
                state_text = "等离子体未建立，真空室抽气中"
            elseif p.key == "ramp" then
                state_text = string.format("电流爬升中 %.0f%%，边界安全因子监控", p.progress * 100)
            elseif p.key == "heat" then
                state_text = string.format("辅助加热投入，总功率 %.1f MW", s.paux)
            elseif p.key == "rampdown" then
                state_text = "电流下降，偏滤器热负荷回落"
            else
                state_text = string.format("%s，位形反馈已锁定", p.name)
            end
            st(page.plasma_state, state_text)
            sc(page.plasma_state, s.ip > 0.05 and C.ink2 or C.ink3)

            local chip_bg = C.green
            if p.key == "heat" then chip_bg = C.plasma
            elseif p.key == "ramp" then chip_bg = C.ion
            elseif p.key == "cooldown" then chip_bg = C.panel3 end
            chip.set(p.name, (p.key == "cooldown") and C.ink2 or C.bg0, chip_bg)

            st(page.ph_shot, string.format("第 %d 炮，%s", theme.n(s.shot), conf.machine.campaign))
            st(page.ph_time, string.format("T+ %d s", theme.n(p.t_plus)))

            local idle = (p.key == "cooldown")
            local abort_off = s.ip < 0.05
            local sig = (idle and "1" or "0") .. (abort_off and "1" or "0")
            if sig ~= btn_sig then
                btn_sig = sig
                pcall(function()
                    page.btn_start:set_text(idle and "启动" or "运行中")
                    page.btn_start:set_disabled(not idle)
                    page.btn_abort:set_disabled(abort_off)
                end)
            end

            for i, seg in ipairs(page.segs) do
                local v = 0
                if i < p.index then
                    v = 100
                elseif i == p.index then
                    v = p.progress * 100
                end
                sb(seg.bar, v)
                local col = C.ink3
                if i < p.index then
                    col = theme.mix(seg.def.color, C.bg1, 0.55)
                elseif i == p.index then
                    col = seg.def.color
                end
                sc(seg.label, col)
            end
        end

        -- ===== 后半：KPI + 子系统 + 磁约束 + 事件（2 秒一轮）=====
        if back then
            local kv = {
                string.format("%.2f", s.bt),
                string.format("%.1f", s.energy),
                string.format("%.2f", s.q),
                string.format("%.2f", s.h98),
            }
            for i, k in ipairs(page.kpis) do
                st(k.val, kv[i])
                if i == 3 then sc(k.val, s.q > 1 and C.green or C.ink) end
            end

            local on = 0
            for i, t in ipairs(page.tiles) do
                local d = sim.device(t.def.key)
                if d and d.on then on = on + 1 end
                st(t.st, d and d.on and "运行" or "停止")
                sc(t.st, d and d.on and C.green or C.ink3)
                sc(t.dot, d and d.on and C.green or C.ink3)
            end
            st(page.dev_count, string.format("%d / %d 在线", on, #page.tiles))

            local mv = {
                string.format("%.2f", conf.magnetic.kappa),
                string.format("%.2f", conf.magnetic.delta),
                string.format("%.2f", conf.magnetic.q95),
                string.format("%.2f", s.ip > 0.05 and conf.magnetic.betaN or 0),
            }
            for i, v in ipairs(page.mvals) do st(v, mv[i]) end

            local risk = theme.n(s.risk)
            st(page.risk_val, string.format("%d%%，%s", risk,
                risk > 60 and "高" or (risk > 30 and "中" or "低")))
            sc(page.risk_val, risk > 60 and C.red or (risk > 30 and C.gold or C.green))
            sb(page.risk_bar, risk)
            local rcol = risk > 60 and C.red or (risk > 30 and C.gold or C.green)
            if page.risk_col ~= rcol then
                page.risk_col = rcol
                pcall(function() page.risk_bar:set_indicator_color(rcol) end)
            end
            st(page.mc_mode, s.rmp and "RMP 投入" or (s.q > 1 and "H 模，ELMy" or "L 模"))
            sc(page.mc_mode, s.rmp and C.violet or C.ink3)

            -- 事件列表：只有出现新事件才重排
            local evs = sim.events(5)
            local e1 = evs[1]
            local esig = e1 and (tostring(e1.tick) .. e1.text) or "-"
            if force or esig ~= ev_sig then
                ev_sig = esig
                for i, row in ipairs(page.event_rows) do
                    local e = evs[i]
                    if e then
                        sc(row.dot, theme.state_color(e.level))
                        st(row.time, e.clock)
                        st(row.text, theme.fit(e.text, 22))
                        sc(row.text, e.level == "danger" and C.red or C.ink2)
                        st(row.sub, string.format("%d 炮，%s", theme.n(e.shot), theme.state_text(e.level)))
                    else
                        sc(row.dot, C.line)
                        st(row.time, "")
                        st(row.text, "")
                        st(row.sub, "")
                    end
                end
            end
            st(page.event_more, string.format("最近 %d 条", #sim.events(30)))
        end
    end
    page.refresh = refresh

    -- ==================== 慢刷新 ====================
    local function slow()
        if not page.alive then return end
        local s = sim.summary()
        -- 量化到 1/6 档：等离子体带每次 set_items 都要重建 12 个椭圆，
        -- 连续调功率会持续分配 LVGL 对象，按档位只在跨档时重建
        local p6 = math.floor(theme.clamp(s.ip / 1.6, 0, 1) * 6 + 0.5) / 6
        page.torus.set_power(p6)
    end
    page.slow = slow

    -- ==================== 帧动画 ====================
    local function frame(f)
        if not page.alive then return end
        -- 粒子轨道很慢，5 fps 足够，没必要每帧刷 12 个对象
        if f % 2 == 0 then
            page.torus.update(f * 0.11)
        end
    end
    page.frame = frame

    function page.destroy()
        page.alive = false
    end

    refresh(true)
    slow()
    frame(0)
    return page
end

return M
