--[[
@module  ui_magnetic
@summary 磁约束页：极向截面 / PF 线圈电流 / 磁扰动频谱 / 破裂预警
@version 1.0
@date    2026.11.12
]]
local theme = require "theme"
local art   = require "art"
local sim   = require "sim"
local conf  = require "conf"

local C = theme.C
local SZ = theme.SZ
local A_LEFT, A_CENTER, A_RIGHT = theme.align_left(), theme.align_center(), theme.align_right()

local M = {}

local L = {
    cross    = { x = 14,  y = 10,  w = 430, h = 370 },
    pf       = { x = 14,  y = 392, w = 430, h = 144 },
    params   = { x = 456, y = 10,  w = 554, h = 150 },
    spectrum = { x = 456, y = 172, w = 554, h = 190 },
    risk     = { x = 456, y = 374, w = 554, h = 162 },
}

local SPEC = { x = 16, y = 40, w = 452, h = 116, cols = 26, rows = 6 }

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 极向截面 ====================
    local cc = theme.card(root, L.cross.x, L.cross.y, L.cross.w, L.cross.h, { radius = 14 })
    theme.label(cc, 14, 8, 240, 18, "极向截面，磁面与线圈", SZ.s, C.ink)
    theme.label(cc, 14, 27, 280, 14, "单零偏滤器位形，双环反馈", SZ.xs, C.ink3)
    local mode = theme.label(cc, 270, 9, 146, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.mode = mode

    local crossbox = theme.box(cc, 0, 42, L.cross.w, 326, C.panel, 0)
    local cross = art.cross_section(crossbox, L.cross.w, 326)
    page.cross = cross

    theme.label(cc, 48, 116, 24, 14, "P1", SZ.xs, C.ink3)
    theme.label(cc, 48, 198, 24, 14, "P2", SZ.xs, C.ink3)
    theme.label(cc, 48, 280, 24, 14, "P3", SZ.xs, C.ink3)
    theme.label(cc, 378, 116, 40, 14, "P4", SZ.xs, C.ink3)
    theme.label(cc, 378, 198, 40, 14, "P5", SZ.xs, C.ink3)
    theme.label(cc, 378, 280, 40, 14, "P6", SZ.xs, C.ink3)
    theme.label(cc, 84, 294, 80, 14, "中心螺线管", SZ.xs, C.ink3)
    theme.label(cc, 252, 322, 80, 14, "X 点", SZ.xs, C.gold)
    theme.label(cc, 250, 82, 90, 14, "真空室", SZ.xs, C.ink3)
    theme.label(cc, 272, 197, 90, 14, "等离子体", SZ.xs, C.plasma)

    -- ==================== PF 线圈 ====================
    local pc = theme.card(root, L.pf.x, L.pf.y, L.pf.w, L.pf.h, { radius = 14 })
    theme.label(pc, 14, 8, 200, 18, "极向场线圈电流", SZ.s, C.ink)
    theme.label(pc, 300, 9, 116, 16, "单位 kA", SZ.xs, C.ink3, A_RIGHT)

    local pfrows = {}
    for i, coil in ipairs(conf.pf_coils) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 14 + col * 206
        local y = 32 + row * 36
        theme.label(pc, x, y + 1, 24, 16, coil.name, SZ.xs, C.ink2)
        local val = theme.label(pc, x + 80, y, 56, 16, "--", SZ.xs, C.ink, A_RIGHT)
        local shape = theme.shape(pc, x + 24, y + 4, 52, 8,
            art.bar_center_items(52, 8, 0, 12, C.ion, C.panel3))
        pfrows[i] = { def = coil, val = val, shape = shape }
    end
    page.pfrows = pfrows

    -- ==================== 平衡参数 ====================
    local qc = theme.card(root, L.params.x, L.params.y, L.params.w, L.params.h, { radius = 14 })
    theme.label(qc, 14, 8, 200, 18, "平衡与位形", SZ.s, C.ink)
    local qmode = theme.label(qc, 360, 9, 180, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.qmode = qmode

    local PDEF = {
        { key = "kappa", cap = "拉长比 κ", fmt = "%.2f" },
        { key = "delta", cap = "三角形变 δ", fmt = "%.2f" },
        { key = "q95",   cap = "安全因子 q95", fmt = "%.2f" },
        { key = "beta",  cap = "归一化比压 βN", fmt = "%.2f" },
        { key = "energy", cap = "储能 W", fmt = "%.1f MJ" },
        { key = "li",    cap = "内感 li", fmt = "%.2f" },
        { key = "zeff",  cap = "有效电荷数 Zeff", fmt = "%.2f" },
        { key = "ngw",   cap = "密度极限比 n/nGW", fmt = "%.2f" },
    }
    local pvals = {}
    for i, d in ipairs(PDEF) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 14 + col * 132
        local y = 34 + row * 56
        theme.label(qc, x, y, 128, 14, d.cap, SZ.xs, C.ink3)
        pvals[i] = theme.label(qc, x, y + 17, 128, 22, "--", SZ.l, C.ink)
    end
    page.pvals = pvals

    -- ==================== 频谱 ====================
    local sc = theme.card(root, L.spectrum.x, L.spectrum.y, L.spectrum.w, L.spectrum.h, { radius = 14 })
    theme.label(sc, 16, 8, 240, 18, "磁扰动频谱，Mirnov 阵列", SZ.s, C.ink)
    local spec_val = theme.label(sc, 330, 9, 210, 16, "", SZ.xs, C.ink3, A_RIGHT)

    theme.label(sc, 16, 26, 200, 12, "频率 1 ~ 12 kHz", SZ.xs, C.ink3)
    theme.label(sc, 300, 26, 168, 12, "时间 →", SZ.xs, C.ink3, A_RIGHT)

    local spec_shape = theme.shape(sc, SPEC.x, SPEC.y, SPEC.w, SPEC.h, {})
    page.spec_shape = spec_shape
    page.spec_val = spec_val

    -- 右侧频率刻度
    for i = 0, 3 do
        local y = SPEC.y + SPEC.h * i / 3
        theme.label(sc, SPEC.x + SPEC.w + 6, y - 6, 56, 12,
            string.format("%.0f kHz", 12 - i * 4), SZ.xs, C.ink3)
    end
    theme.label(sc, 16, 162, 200, 12, "红 = 幅值增强，用于观察 ELM 与锁模演化", SZ.xs, C.ink3)

    -- 频谱数据：26 列环形缓冲
    local spectrum = {}
    for c = 1, SPEC.cols do
        local col = {}
        for r = 1, SPEC.rows do
            col[r] = 0.03 + math.random() * 0.06
        end
        spectrum[c] = col
    end
    page.spectrum = spectrum
    page.spec_tick = 0

    -- ==================== 破裂预警 ====================
    local rc = theme.card(root, L.risk.x, L.risk.y, L.risk.w, L.risk.h, { radius = 14 })
    theme.label(rc, 14, 8, 160, 18, "破裂预警", SZ.s, C.ink)
    local rmp_btn = theme.ghost(rc, 400, 6, 140, 26, "投入 RMP", {
        size = SZ.xs,
        on_click = function()
            sim.set_rmp(not sim.is_rmp())
            page.refresh()
        end,
    })
    page.rmp_btn = rmp_btn

    local risk_val = theme.label(rc, 14, 34, 80, 48, "0%", SZ.hero, C.green)
    theme.label(rc, 96, 62, 40, 20, "%", SZ.m, C.ink3)
    local risk_txt = theme.label(rc, 14, 84, 170, 16, "综合破裂概率", SZ.xs, C.ink3)

    local contributor = {}
    local CDEF = {
        { key = "ngw", cap = "密度极限比" },
        { key = "mhd", cap = "MHD 幅值" },
        { key = "lock", cap = "锁模幅值" },
    }
    for i, d in ipairs(CDEF) do
        local y = 36 + (i - 1) * 30
        theme.label(rc, 200, y, 120, 16, d.cap, SZ.xs, C.ink3)
        local v = theme.label(rc, 380, y, 160, 16, "--", SZ.s, C.ink, A_RIGHT)
        contributor[i] = { def = d, val = v }
    end
    page.contributors = contributor

    local risk_bar = theme.bar(rc, 14, 118, 526, 5, 0, C.green, C.panel3)
    local risk_note = theme.label(rc, 14, 132, 526, 16, "", SZ.xs, C.ink3)
    page.risk_bar = risk_bar
    page.risk_note = risk_note

    -- ==================== 刷新 ====================
    local function refresh()
        if not page.alive then return end
        local s = sim.summary()
        local p = sim.phase()

        page.mode:set_text(p.key == "heat" and "H 模，ELMy" or (s.ip > 0.1 and "L 模" or "待机"))
        page.mode:set_color(p.key == "heat" and C.green or C.ink3)

        -- PF 线圈：电流随位形反馈摆动
        local scale = 0.35 + 0.65 * math.min(1, s.ip / 1.2)
        for i, r in ipairs(page.pfrows) do
            local v = r.def.base * scale * (1 + 0.10 * math.sin(s.tick * 0.33 + i))
            if s.ip < 0.02 then v = 0 end
            r.val:set_text(string.format("%+.1f", v))
            r.val:set_color(v >= 0 and C.ink or C.coral)
            pcall(function()
                r.shape:set_items(art.bar_center_items(52, 8, v, 12, v >= 0 and C.ion or C.coral, C.panel3))
            end)
        end

        -- 平衡参数
        local ngw = theme.clamp(s.ne / 4.88, 0, 1.2)
        local pv = {
            string.format("%.2f", conf.magnetic.kappa),
            string.format("%.2f", conf.magnetic.delta),
            string.format("%.2f", conf.magnetic.q95),
            string.format("%.2f", s.ip > 0.05 and conf.magnetic.betaN or 0),
            string.format("%.1f MJ", s.energy),
            string.format("%.2f", conf.magnetic.li),
            string.format("%.2f", conf.magnetic.zeff),
            string.format("%.2f", ngw),
        }
        for i, lb in ipairs(page.pvals) do lb:set_text(pv[i]) end
        page.qmode:set_text("双零位形，偏差 < 2 mm")

        -- 频谱：每 2 秒推进一列
        page.spec_tick = page.spec_tick + 1
        if page.spec_tick % 2 == 0 then
            table.remove(page.spectrum, 1)
            local col = {}
            local amp = theme.clamp(s.mhd / 4.5, 0, 1)
            for r = 1, SPEC.rows do
                local base = (r == 3) and 0.55 or (0.12 + 0.10 * (SPEC.rows - r))
                col[r] = theme.clamp(amp * base * (0.55 + math.random() * 0.9) + 0.03, 0, 1)
            end
            page.spectrum[#page.spectrum + 1] = col
            pcall(function()
                page.spec_shape:set_items(art.spectrum_items(
                    SPEC.w, SPEC.h, SPEC.cols, SPEC.rows, page.spectrum, C.panel2, C.plasma))
            end)
        end
        page.spec_val:set_text(string.format("幅值 %.2f μT，主频 %.1f kHz", s.mhd, 5.2 + s.mhd * 0.4))

        -- 破裂预警
        local risk = theme.n(s.risk)
        risk_val:set_text(string.format("%d", risk))
        risk_val:set_color(risk > 60 and C.red or (risk > 30 and C.gold or C.green))
        risk_txt:set_text(risk > 60 and "预警等级：高，建议降参数" or
                          (risk > 30 and "预警等级：中，持续监视" or "预警等级：低，窗口安全"))

        local cv = {
            string.format("%.2f", ngw),
            string.format("%.2f μT", s.mhd),
            string.format("%.3f mT", 0.12 + s.mhd * 0.018),
        }
        for i, r in ipairs(page.contributors) do r.val:set_text(cv[i]) end

        if page.risk_bar then
            theme.setbar(page.risk_bar, risk)
            page.risk_bar:set_indicator_color(risk > 60 and C.red or (risk > 30 and C.gold or C.green))
        end
        risk_note:set_text(string.format("下一次破裂窗口预计 %d s 后，偏滤器热负荷 %.1f MW/m2",
            40 + theme.n(s.shot) % 30, 4.2 + s.risk * 0.05))

        pcall(function()
            page.rmp_btn:set_text(s.rmp and "退出 RMP" or "投入 RMP")
        end)
    end
    page.refresh = refresh

    local function slow()
        if not page.alive then return end
        local s = sim.summary()
        page.cross.set_power(theme.clamp(s.ip / 1.6, 0, 1))
    end
    page.slow = slow

    local function frame() end
    page.frame = frame

    function page.destroy()
        page.alive = false
    end

    refresh()
    slow()
    pcall(function()
        page.spec_shape:set_items(art.spectrum_items(
            SPEC.w, SPEC.h, SPEC.cols, SPEC.rows, page.spectrum, C.panel2, C.plasma))
    end)
    return page
end

return M
