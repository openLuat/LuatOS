--[[
@module  ui_overview
@summary 总览页：注塑机剖面动画 + 阶段条 + KPI + 周期环 + 料筒温度 + 执行联锁 + 报警
@version 1.0
@date    2026.11.15
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
    hero   = { x = 14,  y = 10,  w = 640, h = 326 },
    kpi    = { x = 14,  y = 344, w = 640, h = 92 },
    alarm  = { x = 14,  y = 446, w = 640, h = 88 },
    ring   = { x = 664, y = 10,  w = 346, h = 208 },
    temp   = { x = 664, y = 228, w = 346, h = 150 },
    io     = { x = 664, y = 388, w = 346, h = 146 },
}

local MACH = { x = 2, y = 32, w = 636, h = 236 }

-- ===================== 页面 =====================
function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 机台剖面 ====================
    local hero = theme.card(root, L.hero.x, L.hero.y, L.hero.w, L.hero.h, { radius = 10 })
    theme.label(hero, 14, 8, 300, 18, "锁模与注射单元，剖视", SZ.s, C.ink)
    theme.label(hero, 14, 26, 330, 14,
        conf.machine.model .. "，锁模力 " .. conf.machine.clamp .. " kN，螺杆 " .. conf.machine.screw .. " mm",
        SZ.xs, C.ink3)

    local mode_chip = theme.chip(hero, 540, 9, 86, 22, "运行", C.bg0, C.run, SZ.xs)
    page.mode_chip = mode_chip

    -- 机台画在一个独立容器里，art 内部坐标以该容器原点为基准
    local mroot = theme.box(hero, MACH.x, MACH.y, MACH.w, MACH.h, 0x000000, 0, 0)
    local machine = art.imm(mroot, MACH.w, MACH.h, {})
    page.machine = machine

    -- 料筒五段温度标注（跟随 art 的料筒几何）
    local b = machine.barrel
    local seg = b.w / #conf.barrel
    local zlabels = {}
    for i, z in ipairs(conf.barrel) do
        local x = MACH.x + b.x + (i - 1) * seg
        local y = MACH.y + b.y + b.h
        theme.label(hero, x, y + 10, seg, 14, z.name, SZ.xs, C.ink3, A_CENTER)
        zlabels[i] = theme.label(hero, x, y + 23, seg, 14, "--", SZ.xs, C.ink2, A_CENTER)
    end
    page.zlabels = zlabels


    -- 阶段条
    local total = 0
    for _, s in ipairs(conf.stages) do total = total + s.dur end
    local avail_w = L.hero.w - 28
    local segs = {}
    local sx = 14
    for i, s in ipairs(conf.stages) do
        local w = math.floor(avail_w * s.dur / total) - 3
        local bar = theme.bar(hero, sx, 246, w, 6, 0, s.color, C.panel3, 3)
        local lb = theme.label(hero, sx - 2, 256, w + 4, 14, s.short, SZ.xs, C.ink3, A_CENTER)
        segs[i] = { bar = bar, label = lb, def = s }
        sx = sx + w + 3
    end
    page.segs = segs

    theme.label(hero, 14, 288, 40, 16, "周期", SZ.xs, C.ink3)
    local cyc_val = theme.label(hero, 48, 284, 44, 22, "28.0", SZ.m, C.ink)
    theme.label(hero, 94, 290, 24, 14, "s", SZ.xs, C.ink3)
    theme.label(hero, 140, 288, 160, 16, "模号 " .. conf.machine.molds, SZ.xs, C.ink3)
    local stage_val = theme.label(hero, 300, 286, 220, 18, "", SZ.s, C.run, A_RIGHT)
    page.cyc_val = cyc_val
    page.stage_val = stage_val

    -- 运行按钮
    local btn = theme.button(hero, 556, 282, 70, 24, "启动", {
        bg = C.run, size = SZ.xs,
        on_click = function()
            sim.start()
            page.refresh(true)
        end,
    })
    page.btn_start = btn

    -- ==================== KPI ====================
    local kpi = theme.card(root, L.kpi.x, L.kpi.y, L.kpi.w, L.kpi.h, { radius = 10 })
    local KPI_DEF = {
        { key = "cycle", cap = "成型周期", unit = "s" },
        { key = "clamp", cap = "锁模力",   unit = "kN" },
        { key = "pinj",  cap = "注射压力", unit = "bar" },
        { key = "pcav",  cap = "模腔压力", unit = "bar" },
    }
    local kpis = {}
    local cell_w = math.floor(L.kpi.w / 4)
    for i, d in ipairs(KPI_DEF) do
        local x = (i - 1) * cell_w
        if i > 1 then theme.vline(kpi, x, 14, L.kpi.h - 28, C.line) end
        theme.label(kpi, x + 16, 10, cell_w - 24, 16, d.cap, SZ.xs, C.ink3)
        local val = theme.label(kpi, x + 16, 28, cell_w - 24, 40, "--", SZ.xl, C.ink)
        theme.label(kpi, x + 16, 70, cell_w - 24, 14, d.unit, SZ.xs, C.ink3)
        kpis[i] = { def = d, val = val }
    end
    page.kpis = kpis

    -- ==================== 报警 ====================
    local ac = theme.card(root, L.alarm.x, L.alarm.y, L.alarm.w, L.alarm.h, { radius = 10 })
    theme.label(ac, 14, 8, 160, 18, "报警与事件", SZ.s, C.ink)
    local ac_more = theme.label(ac, 380, 9, 246, 16, "", SZ.xs, C.ink3, A_RIGHT)
    local arows = {}
    for i = 1, 3 do
        local y = 28 + (i - 1) * 19
        local dot = theme.box(ac, 14, y + 6, 5, 5, C.green, 2)
        local t = theme.label(ac, 26, y, 46, 14, "", SZ.xs, C.ink3)
        local tx = theme.label(ac, 76, y, 550, 14, "", SZ.xs, C.ink2)
        arows[i] = { dot = dot, time = t, text = tx }
    end
    page.arows = arows
    page.ac_more = ac_more

    -- ==================== 周期环 ====================
    local rc = theme.card(root, L.ring.x, L.ring.y, L.ring.w, L.ring.h, { radius = 10 })
    theme.label(rc, 14, 8, 160, 18, "成型周期", SZ.s, C.ink)
    theme.label(rc, 190, 9, 142, 16, "七段", SZ.xs, C.ink3, A_RIGHT)

    local ring = art.phase_ring(rc, 173, 94, 58, conf.stages, 13)
    page.ring = ring

    local cyc_big = theme.label(rc, 113, 68, 120, 34, "28.0", SZ.xl, C.ink, A_CENTER)
    theme.label(rc, 113, 102, 120, 14, "秒 / 模", SZ.xs, C.ink3, A_CENTER)
    local cyc_stage = theme.label(rc, 113, 120, 120, 16, "合模", SZ.xs, C.run, A_CENTER)
    page.cyc_big = cyc_big
    page.cyc_stage = cyc_stage

    -- 顶部三档：有效/性能/良品
    local oe = {}
    local OE_DEF = {
        { key = "avail", cap = "稼动率", color = C.ice },
        { key = "perf",  cap = "性能",   color = C.run },
        { key = "yield", cap = "良品率", color = C.green },
    }
    for i, d in ipairs(OE_DEF) do
        local x = 14 + (i - 1) * 108
        theme.label(rc, x, 172, 100, 14, d.cap, SZ.xs, C.ink3)
        local v = theme.label(rc, x, 186, 100, 16, "--", SZ.xs, C.ink)
        oe[i] = { def = d, val = v }
    end
    page.oe = oe

    -- ==================== 料筒温度 ====================
    local tc = theme.card(root, L.temp.x, L.temp.y, L.temp.w, L.temp.h, { radius = 10 })
    theme.label(tc, 14, 8, 200, 18, "料筒温度", SZ.s, C.ink)
    local tdev = theme.label(tc, 180, 9, 140, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.tdev = tdev

    local cols = {}
    for i, z in ipairs(conf.barrel) do
        local x = 20 + (i - 1) * 62
        local sh = theme.shape(tc, x, 34, 26, 60, art.temp_column_items(26, 60, 0.5, C.amber, C.panel3, 0.72))
        local nm = theme.label(tc, x - 8, 96, 42, 14, z.name, SZ.xs, C.ink3, A_CENTER)
        local vv = theme.label(tc, x - 8, 110, 42, 14, "--", SZ.xs, C.ink2, A_CENTER)
        cols[i] = { shape = sh, name = nm, val = vv }
    end
    page.cols = cols

    -- 模温与冷却水（一行摘要，避免与第五段温度柱抢位置）
    theme.hline(tc, 14, 126, L.temp.w - 28, C.line)
    local mold_v = theme.label(tc, 14, 130, 170, 14, "模温 -- / -- ℃", SZ.xs, C.ink3)
    local flow_v = theme.label(tc, 188, 130, 144, 14, "", SZ.xs, C.ink3, A_RIGHT)
    page.mold_v = mold_v
    page.flow_v = flow_v

    -- ==================== 执行与联锁 ====================
    local ic = theme.card(root, L.io.x, L.io.y, L.io.w, L.io.h, { radius = 10 })
    theme.label(ic, 14, 8, 160, 18, "执行与联锁", SZ.s, C.ink)
    local io_cnt = theme.label(ic, 200, 9, 132, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.io_cnt = io_cnt

    -- 4 个联锁条件
    local LOCK = {
        { di = 3,  name = "安全门" },
        { di = 4,  name = "模到位" },
        { di = 6,  name = "料温" },
        { di = 5,  name = "手原点" },
    }
    local locks = {}
    for i, d in ipairs(LOCK) do
        local x = 14 + (i - 1) * 82
        local box = theme.box(ic, x, 33, 76, 24, C.panel2, 5)
        local led = theme.led(ic, x + 8, 41, 8, C.run)
        theme.label(ic, x + 22, 33, 50, 24, d.name, SZ.xs, C.ink2)
        locks[i] = { box = box, led = led, def = d }
    end
    page.locks = locks

    -- 8 个 DO 输出
    theme.label(ic, 14, 64, 120, 14, "输出 Q0.0 - Q0.7", SZ.xs, C.ink3)
    local douts = {}
    for i = 1, 8 do
        local x = 14 + (i - 1) * 40
        local box = theme.box(ic, x, 82, 34, 20, C.panel2, 4)
        local lb = theme.label(ic, x, 82, 34, 20, "Q0." .. (i - 1), SZ.xs, C.ink3, A_CENTER)
        douts[i] = { box = box, label = lb }
    end
    page.douts = douts

    -- ==================== 刷新 ====================
    --[[
    总览页每秒刷新的字段约 50 个。逐条 set_text 会让 LVGL 反复重排文本、
    重绘脏区，单帧容易超过 110 ms 的采样周期，把 SoC 的静态事件池顶满
    （日志 soc_send_event_to_task ... no free static event）。
    这里做三层降载：
      1、值不变不写：文本、颜色、进度条分别缓存
      2、前排（阶段条 + 读数）每秒刷，后排（周期环 + 温度 + 联锁）隔秒刷
      3、曲线与图元按量化档位重建，不跟连续值
    ]]
    local tcache, ccache, bcache = {}, {}, {}
    local function st(lb, txt)
        if tcache[lb] ~= txt then
            tcache[lb] = txt
            lb:set_text(txt)
        end
    end
    local function sc(obj, col, method)
        if ccache[obj] ~= col then
            ccache[obj] = col
            pcall(function() obj[method or "set_color"](obj, col) end)
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
    local last_alarm = ""
    local btn_sig = ""

    local function refresh(force)
        if not page.alive then return end
        round = round + 1
        local s = sim.summary()
        local stg = sim.stage()
        local mode, mode_text = sim.mode()
        local back = force or (round % 2 == 0)

        -- ===== 前排：状态 + 阶段 =====
        st(page.cyc_val, string.format("%.1f", s.cycle_time))
        st(page.stage_val, stg.name .. " " .. theme.n(stg.progress * 100) .. "%")
        sc(page.stage_val, stg.color)

        local chip_bg = C.run
        if mode == "fault" then chip_bg = C.red
        elseif mode == "idle" then chip_bg = C.amber end
        page.mode_chip.set(mode_text, C.bg0, chip_bg)

        for i, seg in ipairs(page.segs) do
            local v = 0
            if s.running then
                if i < stg.index then v = 100
                elseif i == stg.index then v = stg.progress * 100 end
            end
            sb(seg.bar, v)
            local col = C.ink3
            if i < stg.index then col = theme.mix(seg.def.color, C.bg1, 0.55)
            elseif i == stg.index then col = seg.def.color end
            sc(seg.label, col)
        end

        local sig = (s.running and "1" or "0") .. (s.fault and "1" or "0")
        if sig ~= btn_sig then
            btn_sig = sig
            pcall(function()
                page.btn_start:set_text(s.running and "运行中" or (s.fault and "已故障" or "启动"))
                page.btn_start:set_disabled(s.running or (s.fault ~= nil))
            end)
        end

        -- ===== 后排：KPI + 环 + 温度 + 联锁 =====
        if back then
            local kv = {
                string.format("%.1f", s.cycle_time),
                string.format("%d", theme.n(s.clamp_kN)),
                string.format("%d", theme.n(s.p_inj)),
                string.format("%d", theme.n(s.p_cav)),
            }
            for i, k in ipairs(page.kpis) do st(k.val, kv[i]) end

            st(page.cyc_big, string.format("%.1f", s.cycle_time))
            st(page.cyc_stage, stg.name)
            sc(page.cyc_stage, stg.color)
            page.ring.set(stg.index, s.running and stg.progress or 0)

            local ov = {
                string.format("%.1f%%", s.avail),
                string.format("%.1f%%", s.perf),
                string.format("%.1f%%", s.yield_pct),
            }
            for i, o in ipairs(page.oe) do
                st(o.val, ov[i])
                sc(o.val, o.def.color)
            end

            -- 料筒温度：每列按偏差改色，形状按 0.5 ℃ 量化重建
            local zones = sim.zones()
            local inband = 0
            for i, z in ipairs(zones) do
                local col = theme.deviation_color(z.dev, 3)
                st(page.zlabels[i], string.format("%.0f", z.value))
                st(page.cols[i].val, string.format("%+.1f", z.dev))
                sc(page.cols[i].val, col)
                sc(page.zlabels[i], col)
                local key = string.format("%.1f", z.value)
                local c = page.cols[i]
                if c.key ~= key or force then
                    c.key = key
                    pcall(function()
                        c.shape:set_items(art.temp_column_items(26, 60, z.pct, col, C.panel3, 0.75))
                    end)
                end
                if z.level == "ok" then inband = inband + 1 end
            end
            st(page.tdev, string.format("%d/%d 段在带内", inband, #zones))
            sc(page.tdev, inband == #zones and C.run or C.amber)

            st(page.mold_v, string.format("模温 %.1f / %.1f ℃", s.mold_t, s.mold_t2))
            st(page.flow_v, string.format("冷却水 %.1f ℃", s.water_t))

            local di, dob = sim.di_bits(), sim.do_bits()
            for i, l in ipairs(page.locks) do
                local on = di[l.def.di]
                l.led.set(on and C.run or C.red)
                pcall(function() l.box:set_color(on and C.panel2 or C.panel3) end)
            end
            local on_cnt = 0
            for i, d in ipairs(page.douts) do
                local on = dob[i]
                if on then on_cnt = on_cnt + 1 end
                pcall(function()
                    d.box:set_color(on and C.run or C.panel2)
                    d.label:set_color(on and C.bg0 or C.ink3)
                end)
            end
            st(page.io_cnt, string.format("%d / 8 输出", on_cnt))

            -- 事件：只有签名变化才重排
            local evs = sim.events(3)
            local e1 = evs[1]
            local esig = e1 and (tostring(e1.tick) .. e1.text) or "-"
            if force or esig ~= last_alarm then
                last_alarm = esig
                for i, row in ipairs(page.arows) do
                    local e = evs[i]
                    if e then
                        sc(row.dot, theme.state_color(e.level))
                        st(row.time, e.clock)
                        st(row.text, theme.fit(e.text, 34))
                        sc(row.text, e.level == "danger" and C.red or (e.level == "warn" and C.amber or C.ink2))
                    else
                        sc(row.dot, C.line)
                        st(row.time, "")
                        st(row.text, "")
                    end
                end
            end
            st(page.ac_more, string.format("累计 %d 条", theme.n(sim.event_count())))
        end
    end
    page.refresh = refresh

    -- ==================== 慢刷新：图元按量化档位重建 ====================
    local function slow()
        if not page.alive then return end
        local zones = sim.zones()
        local colors = {}
        for i, z in ipairs(zones) do
            colors[i] = theme.deviation_color(z.dev, 3)
        end
        page.machine.set_heat(colors)
        -- 取件制品：顶出阶段可见
        local stg = sim.stage()
        local s = sim.summary()
        local visible = s.running and (stg.key == "eject" or (stg.key == "takeout" and stg.progress < 0.5))
        page.machine.set_part(visible, page.machine.mid_y + 34 * stg.progress)
    end
    page.slow = slow

    -- ==================== 帧动画：模具与螺杆用缓动跟随 ====================
    local dm, ds = 0, 1
    local function frame(f)
        if not page.alive then return end
        local s = sim.summary()
        -- 采样是 1 秒一次，直接用量化值会一顿一顿；这里按 9 fps 缓动追上去
        dm = dm + (s.mold_pct - dm) * 0.28
        ds = ds + (s.screw_pct - ds) * 0.28
        page.machine.set_mold(dm)
        page.machine.set_screw(ds)
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
