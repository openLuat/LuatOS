--[[
@module  ui_ladder
@summary 梯形图页：六条在线监视 rung + 通电动画 + CPU 负荷 + 变量表
@version 1.0
@date    2026.11.15
@note    触点与导线用 container 画，改色只调 set_color / set_border_color，
         不需要重建图元；只有 NC 的斜杠是一条静态 line，创建后不再动。
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
    code = { x = 14,  y = 10,  w = 742, h = 466 },
    cpu  = { x = 766, y = 10,  w = 244, h = 150 },
    vars = { x = 766, y = 170, w = 244, h = 306 },
}

-- 单条 rung 的几何：导线中心线在 y+38，触点竖条高 22
local PITCH = 108
local BAR_W = 2
local BAR_H = 22
local CONTACT_GAP = 22

local M_VARS = {
    { tag = "M0.0", name = "运行" },
    { tag = "M0.1", name = "合模允许" },
    { tag = "M0.2", name = "注射中" },
    { tag = "M0.3", name = "保压中" },
    { tag = "M0.4", name = "开模中" },
    { tag = "M0.6", name = "安全链" },
    { tag = "T1",   name = "注射延时" },
    { tag = "T2",   name = "冷却计时" },
}

function M.create(root)
    local page = { root = root, alive = true }

    -- ==================== 梯形图 ====================
    local code = theme.card(root, L.code.x, L.code.y, L.code.w, L.code.h, { radius = 10 })
    theme.label(code, 14, 8, 200, 18, "在线梯形图监视", SZ.s, C.ink)
    local scan_lb = theme.label(code, 420, 9, 306, 16, "", SZ.xs, C.ink3, A_RIGHT)
    page.scan_lb = scan_lb

    -- 左右母线与标题行
    theme.box(code, 22, 32, 2, L.code.h - 48, C.line2, 0)
    theme.box(code, L.code.w - 20, 32, 2, L.code.h - 48, C.line2, 0)
    theme.label(code, 30, 32, 60, 14, "L+", SZ.xs, C.ink3)
    theme.label(code, L.code.w - 62, 32, 34, 14, "M", SZ.xs, C.ink3, A_RIGHT)

    local rungs = {}
    local y = 52
    for idx, def in ipairs(conf.ladder) do
        local has_branch = def.branch ~= nil
        local rh = has_branch and 100 or 62

        -- 标题行：R 序号 + 名称 + 说明
        theme.label(code, 30, y, 24, 14, "R" .. idx, SZ.xs, C.run)
        theme.label(code, 54, y, 98, 14, def.title, SZ.xs, C.ink2)
        theme.label(code, 156, y, 566, 14, def.note, SZ.xs, C.ink3)

        local LINE_Y = y + 41
        local TXT_Y = y + 16
        local CX = 70
        local RAIL_X = L.code.w - 20

        local wires, tags, names, slashes = {}, {}, {}, {}

        for i, e in ipairs(def.rungs) do
            local bx = CX + (i - 1) * PITCH

            if e.kind == "coil" then
                -- 线圈：26x26 的圆角框，右侧一根线接到右母线
                local coil = theme.box(code, bx, LINE_Y - 11, 24, 22, C.panel, 5)
                coil:set_border_color(C.ink3, 2)
                local w2 = theme.box(code, bx + 24, LINE_Y - 1, RAIL_X - (bx + 24), 2, C.line2, 0)
                tags[i] = theme.label(code, bx - 2, TXT_Y, 40, 14, e.var, SZ.xs, C.ink3)
                names[i] = theme.label(code, bx + 34, TXT_Y, 66, 14, e.name, SZ.xs, C.ink3)
                wires[i] = { coil = coil, wire = w2 }
            else
                -- 触点：两根竖条 + 前后导线
                local w1x = (i == 1) and 22 or bx
                local w1 = theme.box(code, w1x, LINE_Y - 1, bx + 26 - w1x, 2, C.line2, 0)
                local b1 = theme.box(code, bx + 26, LINE_Y - BAR_H / 2, BAR_W, BAR_H, C.ink3, 0)
                local b2 = theme.box(code, bx + 26 + CONTACT_GAP, LINE_Y - BAR_H / 2, BAR_W, BAR_H, C.ink3, 0)
                local w2 = theme.box(code, bx + 26 + CONTACT_GAP + BAR_W, LINE_Y - 1,
                    PITCH - (26 + CONTACT_GAP + BAR_W), 2, C.line2, 0)

                -- NC：一条斜杠（静态，不参与通电动画）
                if e.kind == "nc" then
                    slashes[i] = theme.shape(code, bx + 22, LINE_Y - 12, 26, 24, {
                        { type = "line", x1 = 2, y1 = 20, x2 = 24, y2 = 4,
                          color = C.ink2, width = 2, opacity = 255 },
                    })
                end

                tags[i] = theme.label(code, bx + 2, TXT_Y, 44, 14, e.var, SZ.xs, C.ink3)
                names[i] = theme.label(code, bx + 48, TXT_Y, 56, 14, e.name, SZ.xs, C.ink3)
                wires[i] = { wire1 = w1, bar1 = b1, bar2 = b2, wire2 = w2 }
            end
        end

        -- 自锁支路：与第一个触点并联，画在主回路下方
        local branch
        if has_branch then
            local b = def.branch
            local bx = CX
            local by = y + 80
            branch = {
                v1 = theme.box(code, bx, LINE_Y + 1, 2, by - LINE_Y, C.line2, 0),
                v2 = theme.box(code, bx + PITCH, LINE_Y + 1, 2, by - LINE_Y, C.line2, 0),
                h1 = theme.box(code, bx, by, 26, 2, C.line2, 0),
                bar1 = theme.box(code, bx + 26, by - BAR_H / 2, BAR_W, BAR_H, C.ink3, 0),
                bar2 = theme.box(code, bx + 26 + CONTACT_GAP, by - BAR_H / 2, BAR_W, BAR_H, C.ink3, 0),
                h2 = theme.box(code, bx + 26 + CONTACT_GAP + BAR_W, by,
                    PITCH - (26 + CONTACT_GAP + BAR_W), 2, C.line2, 0),
                tag = theme.label(code, bx + 2, by - 28, 44, 14, b.var, SZ.xs, C.ink3),
                name = theme.label(code, bx + 48, by - 28, 56, 14, b.name, SZ.xs, C.ink3),
            }
        end

        rungs[idx] = { def = def, wires = wires, tags = tags, names = names,
                       slashes = slashes, branch = branch }
        y = y + rh
    end
    page.rungs = rungs

    -- ==================== CPU ====================
    local cp = theme.card(root, L.cpu.x, L.cpu.y, L.cpu.w, L.cpu.h, { radius = 10 })
    theme.label(cp, 14, 8, 150, 18, "CPU 与扫描", SZ.s, C.ink)
    local cpu_chip = theme.chip(cp, 168, 9, 62, 20, "RUN", C.bg0, C.run, SZ.xs)
    page.cpu_chip = cpu_chip

    theme.label(cp, 14, 32, 90, 14, "扫描周期", SZ.xs, C.ink3)
    local scan_big = theme.label(cp, 14, 46, 100, 30, "3.4", SZ.xl, C.ink)
    theme.label(cp, 88, 56, 30, 14, "ms", SZ.xs, C.ink3)

    theme.label(cp, 14, 82, 80, 14, "CPU 负荷", SZ.xs, C.ink3)
    local cpu_val = theme.label(cp, 168, 82, 62, 14, "--", SZ.xs, C.ink, A_RIGHT)
    local cpu_bar = theme.bar(cp, 14, 100, 216, 5, 0, C.run, C.panel3)
    page.scan_big = scan_big
    page.cpu_val = cpu_val
    page.cpu_bar = cpu_bar

    theme.label(cp, 14, 112, 216, 14, conf.plc.cpu .. "，" .. conf.plc.firmware, SZ.xs, C.ink3)
    local task_lb = theme.label(cp, 14, 128, 216, 14, "", SZ.xs, C.ink3)
    page.task_lb = task_lb

    -- ==================== 变量表 ====================
    local vt = theme.card(root, L.vars.x, L.vars.y, L.vars.w, L.vars.h, { radius = 10 })
    theme.label(vt, 14, 8, 150, 18, "变量监视", SZ.s, C.ink)
    theme.label(vt, 130, 9, 100, 16, "位 / 定时器", SZ.xs, C.ink3, A_RIGHT)

    local vrows = {}
    for i, d in ipairs(M_VARS) do
        local y2 = 34 + (i - 1) * 30
        theme.hline(vt, 14, y2 + 26, L.vars.w - 28, C.line)
        local led = theme.led(vt, 14, y2 + 6, 8, C.ink3)
        theme.label(vt, 30, y2, 52, 16, d.tag, SZ.xs, C.ink2)
        theme.label(vt, 86, y2, 90, 16, d.name, SZ.xs, C.ink3)
        local val = theme.label(vt, 176, y2, 54, 16, "OFF", SZ.xs, C.ink3, A_RIGHT)
        vrows[i] = { led = led, val = val, def = d }
    end
    page.vrows = vrows

    theme.label(vt, 14, 286, 216, 14, "橙色为强制值，灰色为实时值", SZ.xs, C.ink3)

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
    local function sb(bar, v)
        if not bar then return end
        v = theme.n(v)
        if bcache[bar] ~= v then
            bcache[bar] = v
            theme.setbar(bar, v)
        end
    end

    -- 单条 rung 的通电求解：与 PLC 的扫描顺序一致，从左到右逐级传递
    local function solve(def, bits)
        local on = true
        local res = {}
        for i, e in ipairs(def.rungs) do
            local b = bits[e.var] and true or false
            res[i] = { before = on, bit = b, engaged = false, closed = false }
            if e.kind == "no" then
                -- 自锁支路与第一个触点并联
                if i == 1 and def.branch then
                    b = b or (bits[def.branch.var] and true or false)
                    res[i].branch_on = b
                end
                res[i].closed = b
                on = on and b
            elseif e.kind == "nc" then
                res[i].closed = not b
                on = on and (not b)
            elseif e.kind == "coil" then
                res[i].engaged = on
            end
            res[i].after = on
        end
        return res
    end

    local function refresh()
        if not page.alive then return end
        local s = sim.summary()
        local bits = sim.bits()

        -- CPU 卡片
        st(page.scan_big, string.format("%.1f", s.scan))
        sb(page.cpu_bar, s.cpu)
        st(page.cpu_val, string.format("%d%%", theme.n(s.cpu)))
        sc(page.cpu_val, s.cpu > 40 and C.amber or C.ink)
        st(page.task_lb, string.format("6 任务，%s", conf.plc.rack))
        local mode = sim.mode()
        page.cpu_chip.set(mode == "fault" and "STOP" or "RUN", C.bg0,
            mode == "fault" and C.red or C.run)

        -- 梯形图
        for _, r in ipairs(page.rungs) do
            local res = solve(r.def, bits)
            for i, e in ipairs(r.def.rungs) do
                local rr = res[i]
                local w = r.wires[i]
                local on_col = C.run
                local off_col = C.line2
                if e.kind == "coil" then
                    pcall(function()
                        w.coil:set_border_color(rr.engaged and C.run or C.ink3, 2)
                        w.coil:set_color(rr.engaged and theme.mix(C.panel, C.run, 0.22) or C.panel)
                    end)
                    sc(w.wire, rr.engaged and C.run or C.line2)
                else
                    -- 触点只有在“通电且闭合”时才点亮：
                    -- 只按位值着色会让一条已经断电的支路看起来仍然导通
                    local bar_col = (rr.before and rr.closed) and C.run or C.ink3
                    sc(w.bar1, bar_col)
                    sc(w.bar2, bar_col)
                    sc(w.wire1, rr.before and C.run or C.line2)
                    sc(w.wire2, rr.after and C.run or C.line2)
                end
                sc(r.tags[i], ((rr.before and rr.closed) or rr.engaged) and C.ink or C.ink3)
            end
            -- 自锁支路
            if r.branch then
                local bb = bits[r.def.branch.var] and true or false
                local feed = res[1].before
                local col = (feed and bb) and C.run or C.line2
                sc(r.branch.v1, col)
                sc(r.branch.v2, col)
                sc(r.branch.h1, col)
                sc(r.branch.h2, col)
                sc(r.branch.bar1, (feed and bb) and C.run or C.ink3)
                sc(r.branch.bar2, (feed and bb) and C.run or C.ink3)
                sc(r.branch.tag, (feed and bb) and C.ink or C.ink3)
            end
        end

        -- 变量表
        for _, row in ipairs(page.vrows) do
            local b = bits[row.def.tag] and true or false
            row.led.set(b and C.run or C.ink3)
            st(row.val, b and "ON" or "OFF")
            sc(row.val, b and C.run or C.ink3)
        end

        st(page.scan_lb, string.format("扫描 %.1f ms，位映像 %d 点", s.scan, 44))
    end
    page.refresh = refresh

    local function slow()
        if not page.alive then return end
    end
    page.slow = slow

    function page.destroy()
        page.alive = false
    end

    refresh()
    return page
end

return M
