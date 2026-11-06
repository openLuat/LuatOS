--[[
@module  ui_flight
@summary AeroDeck 航班详情：保障节点时间轴、舱单、机位调整与现场操作
@version 1.0
@date    2026.11.05
]]
local conf = require "conf"
local theme = require "theme"
local art = require "art"
local sim = require "sim"
local app = require "app"

local C, SZ = theme.C, theme.SZ
local CT, RT = airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT

local M = {}

local function pad2(n) return string.format("%02d", n) end

-- 把"分钟"转成 HH:MM
local function hm(min)
    min = (math.floor(min) + 1440) % 1440
    return pad2(math.floor(min / 60)) .. ":" .. pad2(min % 60)
end

-- 保障节点计划时刻：推出前 1.6 小时开工，8 个节点均分
local function node_time(f, i)
    local std = sim.minutes_of(f.std)
    return hm(std - (#conf.nodes - i + 1) * 12)
end

function M.build(p, idx)
    local alive = true
    local index = idx or 1
    local f = sim.flight(index) or sim.flight(1)
    index = f.idx

    local ui = { nodes = {} }
    local refresh

    local _, clock = app.subbar(p, "航班保障详情", "机坪指挥 · 单机全流程", function()
        app.go("apron")
    end)

    ------------------------------------------------------------------
    -- 头部：航班身份 + 关键状态
    ------------------------------------------------------------------
    local hc = theme.card(p, 16, 66, 992, 84, { color = C.panel, radius = 12 })
    local acbox = theme.card(hc, 14, 14, 56, 56, { color = 0x0B2231, radius = 14,
        border_color = C.line2, border_width = 1 })
    art.icon(acbox, "plane", 12, 12, 32, C.cyan)

    ui.cs = theme.label(hc, 82, 8, 210, 32, f.cs, SZ.xl, C.ink)
    ui.sub = theme.label(hc, 82, 44, 230, 18, "", SZ.xs, C.ink3)
    theme.vline(hc, 310, 14, 56, C.line)

    theme.label(hc, 330, 12, 80, 16, "机位", SZ.xs, C.ink3)
    ui.gate = theme.label(hc, 330, 28, 80, 34, f.gate, SZ.xl, C.cyan)
    theme.label(hc, 420, 12, 100, 16, "计划起飞", SZ.xs, C.ink3)
    ui.std = theme.label(hc, 420, 30, 100, 28, f.std, SZ.l, C.ink)
    ui.delay = theme.label(hc, 420, 56, 100, 18, "", SZ.xs, C.ink3)
    theme.label(hc, 530, 12, 160, 16, "当前状态", SZ.xs, C.ink3)
    ui.status = theme.label(hc, 530, 28, 180, 30, "", SZ.l, C.ink)
    ui.next = theme.label(hc, 530, 58, 190, 18, "", SZ.xs, C.ink3)

    ui.level = theme.chip(hc, 884, 12, 94, 26, "", C.ink2, C.panel2, SZ.xs)
    ui.pct = theme.label(hc, 700, 44, 174, 18, "", SZ.xs, C.ink3, RT)
    ui.bar = theme.segbar(hc, 740, 64, 134, 7, 24, C.cyan, 0x16283C, 2)

    ------------------------------------------------------------------
    -- 保障节点时间轴
    ------------------------------------------------------------------
    local tc = theme.card(p, 16, 160, 600, 258)
    theme.label(tc, 14, 8, 200, 22, "保障节点时间轴", SZ.m, C.ink)
    ui.tl_note = theme.label(tc, 220, 8, 366, 22, "", SZ.xs, C.ink3, RT)

    for i, n in ipairs(conf.nodes) do
        local y = 34 + (i - 1) * 26
        local row = theme.card(tc, 10, y, 580, 24, {
            color = C.panel2, radius = 6, border_color = C.line, border_width = 1,
        })
        local it = { row = row }
        it.no = theme.label(row, 8, 3, 18, 18, pad2(i), SZ.xs, C.ink3)
        it.dot = app.dot(row, 32, 11, 2, C.line)
        it.name = theme.label(row, 42, 3, 70, 18, n.name, SZ.s, C.ink)
        it.tag = theme.chip(row, 112, 2, 44, 20, n.tag, C.ink3, C.panel3, SZ.xs)
        it.note = theme.label(row, 164, 4, 250, 16, n.note, SZ.xs, C.ink3)
        it.chip = theme.chip(row, 424, 2, 66, 20, "", C.ink3, C.panel3, SZ.xs)
        it.time = theme.label(row, 500, 4, 62, 16, node_time(f, i), SZ.xs, C.ink3, RT)
        ui.nodes[i] = it
    end

    ------------------------------------------------------------------
    -- 舱单与载重
    ------------------------------------------------------------------
    local mc = theme.card(p, 624, 160, 384, 120)
    theme.label(mc, 14, 8, 220, 22, "舱单与载重", SZ.m, C.ink)
    local mdefs = {
        { name = "旅客", unit = "人" },
        { name = "行李", unit = "件" },
        { name = "航油", unit = "%" },
        { name = "已延误", unit = "分" },
    }
    for i, d in ipairs(mdefs) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local cell = theme.card(mc, 14 + col * 184, 34 + row * 42, 172, 36,
            { color = C.panel2, radius = 8, border_color = C.line, border_width = 1 })
        theme.label(cell, 12, 10, 80, 16, d.name, SZ.xs, C.ink3)
        local val = theme.label(cell, 12, 6, 100, 24, "--", SZ.l, C.ink, RT)
        theme.label(cell, 118, 11, 44, 16, d.unit, SZ.xs, C.ink3)
        ui["m" .. i] = val
    end

    ------------------------------------------------------------------
    -- 现场操作
    ------------------------------------------------------------------
    local oc = theme.card(p, 624, 288, 384, 130)
    theme.label(oc, 14, 8, 200, 22, "现场操作", SZ.m, C.ink)
    ui.ops_note = theme.label(oc, 120, 8, 250, 22, "", SZ.xs, C.ink3, RT)

    ui.btn_adv = theme.button(oc, 14, 32, 168, 34, "推进下一节点", {
        bg = C.cyan, fg = C.bg0, size = SZ.s,
        on_click = function()
            if not alive then return end
            if f.gone or f.node >= #conf.nodes then
                app.toast("该航班保障流程已结束", C.ink3)
                return
            end
            local _, txt = sim.advance(index)
            app.toast(txt or "已推进", C.cyan)
            if refresh then refresh() end
        end,
    })
    ui.btn_deice = theme.ghost(oc, 198, 32, 172, 34, "完成除冰", {
        border = C.orange, fg = C.orange,
        on_click = function()
            if not alive then return end
            local ok, msg = sim.deice_on(index)
            app.toast(msg, ok and C.green or C.gold)
            if refresh then refresh() end
        end,
    })
    theme.ghost(oc, 14, 74, 168, 34, "全部推进完成", {
        on_click = function()
            if not alive then return end
            for _ = 1, #conf.nodes do
                if f.node < #conf.nodes then sim.advance(index) end
            end
            app.toast(f.cs .. " 保障完成，等待推出", C.green)
            if refresh then refresh() end
        end,
    })
    theme.ghost(oc, 198, 74, 172, 34, "返回机坪", {
        on_click = function() if alive then app.go("apron") end end,
    })
    theme.label(oc, 14, 110, 356, 16,
        "提示：推进节点会实时影响机位占用与准点率", SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 机位调整
    ------------------------------------------------------------------
    local sc = theme.card(p, 16, 428, 600, 156)
    theme.label(sc, 14, 8, 200, 22, "机位调整", SZ.m, C.ink)
    theme.label(sc, 180, 8, 406, 22, "点击空闲机位即可改派（宽体机仅可停靠宽体位）",
        SZ.xs, C.ink3, RT)

    ui.stands = {}
    for i, s in ipairs(sim.stands()) do
        local col = (i - 1) % 6
        local row = math.floor((i - 1) / 6)
        local x = 14 + col * 96
        local y = 34 + row * 48
        local cell = theme.card(sc, x, y, 88, 42, {
            color = C.panel2, radius = 8, border_color = C.line, border_width = 1,
            on_click = function()
                if not alive then return end
                if f.gate == s.id then
                    app.toast("该航班已在本机位", C.ink3)
                    return
                end
                local ok, msg = sim.set_gate(index, s.id)
                if ok then
                    app.toast(msg, C.green)
                    app.go("flight", index)
                else
                    app.toast(msg, C.gold)
                end
            end,
        })
        local id = theme.label(cell, 8, 4, 40, 18, s.id, SZ.s, C.ink2)
        local info = theme.label(cell, 8, 22, 74, 16, "", SZ.xs, C.ink3)
        ui.stands[i] = { cell = cell, id = id, info = info, s = s }
    end
    theme.label(sc, 14, 132, 566, 16,
        "宽体位：A08 / A10 / A12　　窄体位：其余 9 个", SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 本航班事件
    ------------------------------------------------------------------
    local ec = theme.card(p, 624, 428, 384, 156)
    theme.label(ec, 14, 8, 200, 22, "本航班事件", SZ.m, C.ink)
    ui.evt_note = theme.label(ec, 200, 8, 170, 22, "", SZ.xs, C.ink3, RT)
    ui.evts = {}
    for i = 1, 4 do
        local y = 36 + (i - 1) * 28
        local t = theme.label(ec, 14, y + 2, 40, 16, "", SZ.xs, C.ink3)
        local d = app.dot(ec, 58, y + 7, 2, C.ink3)
        local tx = theme.label(ec, 68, y, 300, 22, "", SZ.xs, C.ink2)
        ui.evts[i] = { time = t, dot = d, text = tx }
    end

    ------------------------------------------------------------------
    -- 刷新
    ------------------------------------------------------------------
    function refresh()
        if not alive then return end
        local lv = sim.level(f)
        local col = theme.state_color(lv)

        ui.cs:set_text(f.cs)
        ui.sub:set_text(string.format("%s · %s · %s", f.airline, f.type,
            f.wide and "宽体机" or "窄体机"))
        ui.gate:set_text(f.gate)
        ui.std:set_text(f.std)
        ui.status:set_text(sim.status_text(f))
        ui.status:set_color(f.deice and C.orange or (f.node >= #conf.nodes and C.amber or C.ink))
        ui.delay:set_text(f.delay > 0 and ("延误 " .. f.delay .. " 分钟") or "准点")
        ui.delay:set_color(f.delay > 5 and C.gold or C.green)

        local left = sim.until_std(f)
        ui.next:set_text(f.gone and "已离场" or ("下一步：" .. sim.step_name(f) ..
            (left >= 0 and ("（" .. app.remain_text(left) .. "）") or "")))
        ui.level.set(sim.level_text(f), lv == "ok" and C.green or col)
        ui.level.box:set_border_color(lv == "ok" and C.line or col, 1)
        ui.bar.set(sim.progress(f), f.deice and C.orange or (f.node >= #conf.nodes and C.amber or C.cyan))
        ui.pct:set_text(string.format("保障进度 %.0f%% · %d/%d", sim.progress(f) * 100,
            f.node, #conf.nodes))

        -- 时间轴状态机
        for i, it in ipairs(ui.nodes) do
            if i <= f.node then
                app.dot_paint(it.dot, 2, C.green)
                it.name:set_color(C.ink)
                it.chip.set("完成", C.green)
                it.row:set_border_color(C.line, 1)
                it.time:set_color(C.ink3)
            elseif i == f.node + 1 then
                app.dot_paint(it.dot, 2, f.deice and C.orange or C.amber)
                it.name:set_color(C.ink)
                it.chip.set("进行中", f.deice and C.orange or C.amber)
                it.row:set_border_color(f.deice and C.orange or C.amber, 1)
                it.time:set_color(C.ink2)
            else
                app.dot_paint(it.dot, 2, C.line2)
                it.name:set_color(C.ink3)
                it.chip.set("待执行", C.ink3)
                it.row:set_border_color(C.line, 1)
                it.time:set_color(0x3A5570)
            end
        end
        ui.tl_note:set_text(string.format("已执行 %d / %d · 关舱推出 %s",
            f.node, #conf.nodes, node_time(f, #conf.nodes)))

        ui.m1:set_text(tostring(f.pax))
        ui.m2:set_text(tostring(f.bags))
        ui.m3:set_text(tostring(f.fuel))
        ui.m4:set_text(tostring(f.delay))
        ui.m4:set_color(f.delay > 5 and C.gold or C.green)

        ui.ops_note:set_text(f.deice and "除冰作业待完成" or "保障流程正常")
        ui.ops_note:set_color(f.deice and C.orange or C.ink3)

        -- 机位占用
        for _, it in ipairs(ui.stands) do
            local owner = sim.stand_flight(it.s.id)
            if owner then
                if owner.idx == index then
                    it.info:set_text("本航班")
                    it.info:set_color(C.cyan)
                    it.id:set_color(C.cyan)
                    it.cell:set_color(0x0B2A38)
                    it.cell:set_border_color(C.cyan, 1)
                else
                    it.info:set_text(owner.cs)
                    it.info:set_color(C.ink3)
                    it.id:set_color(C.ink2)
                    it.cell:set_color(C.panel3)
                    it.cell:set_border_color(C.line, 1)
                end
            else
                it.info:set_text(it.s.wide and "宽体·空闲" or "空闲")
                it.info:set_color(C.green)
                it.id:set_color(C.ink2)
                it.cell:set_color(C.panel2)
                it.cell:set_border_color(C.line, 1)
                if it.s.wide and not f.wide then
                    it.info:set_color(0x2F7F66)
                end
            end
        end

        -- 本航班相关事件
        local rel = {}
        for _, a in ipairs(sim.alarms(40)) do
            if string.find(a.text, f.cs, 1, true) then rel[#rel + 1] = a end
            if #rel >= 4 then break end
        end
        for i = 1, 4 do
            local e, a = ui.evts[i], rel[i]
            if a then
                local ac = theme.state_color(a.level)
                e.time:set_text(a.time)
                e.text:set_text(a.text)
                e.text:set_color(a.level == "ok" and C.ink2 or ac)
                app.dot_paint(e.dot, 2, ac)
            else
                e.time:set_text("")
                e.text:set_text("")
            end
        end
        ui.evt_note:set_text(#rel .. " 条记录")
    end

    pcall(refresh)

    return {
        refresh = function() if alive and refresh then pcall(refresh) end end,
        destroy = function() alive = false end,
    }
end

return M
