--[[
@module  ui_io
@summary 点位页：DI / DO / AI / AO 四个映像区 + 强制表 + 背板模块
@version 1.0
@date    2026.11.15
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
    di     = { x = 14,  y = 10,  w = 330, h = 250 },
    dout   = { x = 14,  y = 270, w = 330, h = 250 },
    ai     = { x = 356, y = 10,  w = 330, h = 250 },
    ao     = { x = 356, y = 270, w = 330, h = 250 },
    force  = { x = 698, y = 10,  w = 312, h = 250 },
    module = { x = 698, y = 270, w = 312, h = 250 },
}

-- 可强制的点（演示用）
local FORCE_POINTS = {
    { tag = "M0.2", name = "注射中" },
    { tag = "M0.5", name = "故障位" },
    { tag = "Q0.4", name = "顶针阀" },
    { tag = "M0.4", name = "开模中" },
}

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== DI ====================
    local di = theme.card(root, L.di.x, L.di.y, L.di.w, L.di.h, { radius = 10 })
    theme.label(di, 14, 8, 160, 18, "数字输入 DI", SZ.s, C.ink)
    local di_cnt = theme.label(di, 200, 9, 116, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.di_cnt = di_cnt

    local di_rows = {}
    for i, d in ipairs(conf.di) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 14 + col * 158
        local y = 32 + row * 26
        local led = theme.led(di, x, y + 5, 8, C.ink3)
        theme.label(di, x + 14, y, 40, 16, d.tag, SZ.xs, C.ink2)
        local nm = theme.label(di, x + 54, y, 88, 16, d.name, SZ.xs, C.ink3)
        di_rows[i] = { led = led, name = nm }
    end
    page.di_rows = di_rows

    -- ==================== DO ====================
    local dob = theme.card(root, L.dout.x, L.dout.y, L.dout.w, L.dout.h, { radius = 10 })
    theme.label(dob, 14, 8, 160, 18, "数字输出 DO", SZ.s, C.ink)
    local do_cnt = theme.label(dob, 200, 9, 116, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.do_cnt = do_cnt

    local do_rows = {}
    for i, d in ipairs(conf.dout) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local x = 14 + col * 158
        local y = 32 + row * 26
        local led = theme.led(dob, x, y + 5, 8, C.ink3)
        theme.label(dob, x + 14, y, 40, 16, d.tag, SZ.xs, C.ink2)
        local nm = theme.label(dob, x + 54, y, 88, 16, d.name, SZ.xs, C.ink3)
        do_rows[i] = { led = led, name = nm }
    end
    page.do_rows = do_rows

    -- ==================== AI ====================
    local ai = theme.card(root, L.ai.x, L.ai.y, L.ai.w, L.ai.h, { radius = 10 })
    theme.label(ai, 14, 8, 160, 18, "模拟输入 AI", SZ.s, C.ink)
    theme.label(ai, 200, 9, 116, 16, "0-10 V", SZ.xs, C.ink3, A_RIGHT)

    local ai_rows = {}
    for i, d in ipairs(conf.ai) do
        local y = 32 + (i - 1) * 26
        theme.label(ai, 14, y, 34, 16, d.tag, SZ.xs, C.ink3)
        theme.label(ai, 50, y, 76, 16, d.name, SZ.xs, C.ink3)
        local val = theme.label(ai, 126, y, 62, 16, "--", SZ.xs, C.ink, A_RIGHT)
        theme.label(ai, 194, y, 30, 16, d.unit, SZ.xs, C.ink3)
        local bar = theme.bar(ai, 228, y + 6, 88, 4, 0, d.color, C.panel3)
        ai_rows[i] = { def = d, val = val, bar = bar }
    end
    page.ai_rows = ai_rows

    -- ==================== AO ====================
    local ao = theme.card(root, L.ao.x, L.ao.y, L.ao.w, L.ao.h, { radius = 10 })
    theme.label(ao, 14, 8, 160, 18, "模拟输出 AO", SZ.s, C.ink)
    theme.label(ao, 200, 9, 116, 16, "0-10 V", SZ.xs, C.ink3, A_RIGHT)

    local ao_rows = {}
    for i, d in ipairs(conf.ao) do
        local y = 32 + (i - 1) * 34
        theme.label(ao, 14, y, 34, 16, d.tag, SZ.xs, C.ink3)
        theme.label(ao, 50, y, 76, 16, d.name, SZ.xs, C.ink3)
        local val = theme.label(ao, 126, y, 62, 16, "--", SZ.xs, C.ink, A_RIGHT)
        theme.label(ao, 194, y, 30, 16, d.unit, SZ.xs, C.ink3)
        local bar = theme.bar(ao, 228, y + 6, 88, 4, 0, C.ice, C.panel3)
        ao_rows[i] = { def = d, val = val, bar = bar }
    end
    page.ao_rows = ao_rows

    theme.hline(ao, 14, 176, L.ao.w - 28, C.line)
    theme.label(ao, 14, 186, 296, 14, "比例阀给定时基 20 ms，斜坡 0.4 s", SZ.xs, C.ink3)
    local ao_note = theme.label(ao, 14, 204, 296, 14, "", SZ.xs, C.ink3)
    page.ao_note = ao_note

    -- ==================== 强制表 ====================
    local fc = theme.card(root, L.force.x, L.force.y, L.force.w, L.force.h, { radius = 10 })
    theme.label(fc, 14, 8, 160, 18, "强制表", SZ.s, C.ink)
    local fc_cnt = theme.label(fc, 176, 9, 122, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.fc_cnt = fc_cnt
    theme.label(fc, 14, 28, 284, 14, "点按切换强制，强制值优先于实时映像", SZ.xs, C.ink3)

    local fro = {}
    for i, d in ipairs(FORCE_POINTS) do
        local y = 48 + (i - 1) * 34
        local box = theme.box(fc, 14, y, 284, 28, C.panel2, 5)
        local led = theme.led(fc, 24, y + 10, 8, C.ink3)
        theme.label(fc, 40, y + 6, 48, 16, d.tag, SZ.xs, C.ink2)
        theme.label(fc, 92, y + 6, 100, 16, d.name, SZ.xs, C.ink3)
        local chip = theme.chip(fc, 226, y + 4, 60, 20, "实时", C.ink3, C.panel3, SZ.xs)
        box:set_on_click(function()
            sim.force(d.tag, not sim.is_forced(d.tag))
            page.refresh(true)
        end)
        fro[i] = { box = box, led = led, chip = chip, def = d }
    end
    page.fro = fro

    local btn = theme.ghost(fc, 14, 190, 132, 26, "全部取消强制", {
        size = SZ.xs,
        on_click = function()
            sim.clear_force()
            page.refresh(true)
        end,
    })
    theme.label(fc, 156, 196, 142, 14, "仅在演示中使用", SZ.xs, C.ink3, A_RIGHT)

    -- ==================== 背板模块 ====================
    local md = theme.card(root, L.module.x, L.module.y, L.module.w, L.module.h, { radius = 10 })
    theme.label(md, 14, 8, 160, 18, "背板模块", SZ.s, C.ink)
    local md_cnt = theme.label(md, 176, 9, 122, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.md_cnt = md_cnt

    local mrows = {}
    for i, d in ipairs(conf.modules) do
        local y = 32 + (i - 1) * 32
        theme.hline(md, 14, y + 26, L.module.w - 28, C.line)
        local led = theme.led(md, 14, y + 6, 8, C.green)
        theme.label(md, 30, y, 44, 16, d.tag, SZ.xs, C.ink3)
        theme.label(md, 78, y, 150, 16, d.name, SZ.xs, C.ink2)
        local note = theme.label(md, 228, y, 70, 16, d.note, SZ.xs, C.ink3, A_RIGHT)
        mrows[i] = { led = led, note = note }
    end
    page.mrows = mrows

    theme.label(md, 14, 226, 284, 14, "机架 0，槽位 1-6，总线周期 2 ms", SZ.xs, C.ink3)

    -- ==================== 刷新 ====================
    local tcache, ccache, bcache = {}, {}, {}
    local function st(lb, txt)
        if tcache[lb] ~= txt then
            tcache[lb] = txt
            lb:set_text(txt)
        end
    end
    local function sc(obj, col)
        if ccache[obj] ~= col then
            ccache[obj] = col
            pcall(function() obj:set_color(col) end)
        end
    end
    local function sb(bar, v, col)
        if not bar then return end
        v = theme.n(v)
        if bcache[bar] ~= v then
            bcache[bar] = v
            theme.setbar(bar, v)
        end
        if col then theme.setbar_color(bar, col) end
    end

    local round = 0
    local function refresh(force_all)
        if not page.alive then return end
        round = round + 1
        if not force_all and round % 2 ~= 0 then return end

        local di_b, do_b = sim.di_bits(), sim.do_bits()

        local on_di, on_do = 0, 0
        for i, r in ipairs(page.di_rows) do
            local on = di_b[i]
            if on then on_di = on_di + 1 end
            r.led.set(on and C.run or C.ink3)
            sc(r.name, on and C.ink2 or C.ink3)
        end
        for i, r in ipairs(page.do_rows) do
            local on = do_b[i]
            if on then on_do = on_do + 1 end
            r.led.set(on and C.run or C.ink3)
            sc(r.name, on and C.ink2 or C.ink3)
        end
        st(page.di_cnt, string.format("%d / 16 点", on_di))
        st(page.do_cnt, string.format("%d / 16 点", on_do))

        for i, r in ipairs(page.ai_rows) do
            local a = sim.ai_values()[i]
            local fmt = (a.def.max >= 1000) and "%.0f" or "%.1f"
            st(r.val, string.format(fmt, a.value))
            sb(r.bar, a.pct)
        end
        for i, r in ipairs(page.ao_rows) do
            local a = sim.ao_values()[i]
            st(r.val, string.format("%.1f", a.value))
            sb(r.bar, a.pct)
        end
        local s = sim.summary()
        st(page.ao_note, string.format("液压油温 %.1f ℃，伺服电流 %.1f A", s.oil_t, s.servo_a))

        -- 强制表
        local n = 0
        for _, r in ipairs(page.fro) do
            local on = sim.is_forced(r.def.tag)
            if on then n = n + 1 end
            r.led.set(on and C.amber or C.ink3)
            r.chip.set(on and "强制" or "实时",
                on and C.bg0 or C.ink3,
                on and C.amber or C.panel3)
            pcall(function() r.box:set_color(on and theme.mix(C.panel2, C.amber, 0.14) or C.panel2) end)
        end
        st(page.fc_cnt, n > 0 and (n .. " 点强制") or "无强制")
        sc(page.fc_cnt, n > 0 and C.amber or C.ink3)

        st(page.md_cnt, string.format("%d / %d 在线", #conf.modules, #conf.modules))
    end
    page.refresh = refresh

    local function slow()
        if not page.alive then return end
    end
    page.slow = slow

    function page.destroy()
        page.alive = false
    end

    refresh(true)
    return page
end

return M
