--[[
@module  ui_settings
@summary AeroDeck 设置页：机坪资源调度、机位总览、演示控制与系统信息
@version 1.0
@date    2026.11.05
]]
local conf = require "conf"
local theme = require "theme"
local art = require "art"
local sim = require "sim"
local app = require "app"

local C, SZ = theme.C, theme.SZ
local RT = airui.TEXT_ALIGN_RIGHT

local M = {}

function M.build(p)
    local alive = true
    local ui = { res = {}, stands = {}, sys = {} }
    local refresh

    local _, clock = app.subbar(p, "指挥设置", "机坪指挥 · 资源与系统", function()
        app.go("apron")
    end)
    ui.clock = clock

    ------------------------------------------------------------------
    -- 机坪资源
    ------------------------------------------------------------------
    local rc = theme.card(p, 16, 66, 500, 240)
    theme.label(rc, 14, 8, 200, 22, "机坪资源", SZ.m, C.ink)
    ui.res_note = theme.label(rc, 180, 8, 306, 22, "", SZ.xs, C.ink3, RT)

    for i, r in ipairs(sim.resources()) do
        local y = 38 + (i - 1) * 48
        local row = theme.card(rc, 12, y, 476, 42, { color = C.panel2, radius = 8,
            border_color = C.line, border_width = 1 })
        art.icon(row, r.icon, 10, 10, 22, C.cyan)
        local name = theme.label(row, 40, 5, 140, 18, r.name, SZ.s, C.ink)
        local info = theme.label(row, 40, 23, 160, 16, "", SZ.xs, C.ink3)
        local bar = theme.segbar(row, 200, 18, 130, 7, 12, C.cyan, 0x16283C, 2)

        local function step(d)
            if not alive then return end
            sim.res_add(r.key, d)
            if refresh then refresh() end
        end
        local minus = theme.ghost(row, 344, 6, 58, 30, "-1", {
            border = C.line2, on_click = function() step(-1) end,
        })
        local plus = theme.button(row, 408, 6, 58, 30, "+1", {
            bg = 0x0B2A38, fg = C.cyan, border = C.line2, border_width = 1,
            pressed = C.panel3, radius = 9, size = SZ.s,
            on_click = function() step(1) end,
        })
        ui.res[i] = { row = row, name = name, info = info, bar = bar,
                      minus = minus, plus = plus, r = r }
    end
    theme.label(rc, 14, 226, 470, 14,
        "资源数量为演示参数：除冰车不足时航班无法放行，摆渡车不足会压低准点率",
        SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 演示控制
    ------------------------------------------------------------------
    local dc = theme.card(p, 528, 66, 480, 240)
    theme.label(dc, 14, 8, 200, 22, "演示控制", SZ.m, C.ink)
    ui.mode_note = theme.label(dc, 180, 8, 286, 22, "", SZ.xs, C.ink3, RT)

    ui.pause_box = theme.card(dc, 14, 36, 140, 44, {
        color = C.panel2, radius = 10, border_color = C.line, border_width = 1,
        on_click = function()
            if not alive then return end
            sim.paused = not sim.paused
            app.toast(sim.paused and "演示已暂停" or "演示已继续",
                sim.paused and C.gold or C.green)
            if refresh then refresh() end
        end,
    })
    ui.pause_dot = app.dot(ui.pause_box, 16, 19, 3, C.green)
    ui.pause_text = theme.label(ui.pause_box, 26, 12, 108, 20, "暂停演示", SZ.s, C.ink)

    theme.ghost(dc, 166, 36, 140, 44, "单步推演", {
        on_click = function()
            if not alive then return end
            local was = sim.paused
            sim.paused = false
            sim.tick()
            sim.paused = was
            app.toast("已推演一个采样周期", C.cyan)
            if refresh then refresh() end
        end,
    })
    theme.ghost(dc, 318, 36, 148, 44, "重置演示", {
        border = C.gold, fg = C.gold,
        on_click = function()
            if not alive then return end
            sim.init()
            app.toast("演示数据已重置", C.green)
            app.go("settings")
        end,
    })

    theme.hline(dc, 14, 92, 452, C.line)
    theme.label(dc, 14, 100, 200, 20, "系统信息", SZ.s, C.ink2)

    local sdefs = { "运行时长", "采样周期", "在场航班", "事件记录" }
    for i, n in ipairs(sdefs) do
        local y = 126 + (i - 1) * 24
        theme.label(dc, 14, y, 120, 18, n, SZ.xs, C.ink3)
        ui.sys[i] = theme.label(dc, 140, y, 320, 18, "--", SZ.xs, C.ink2, RT)
    end
    ui.fw = theme.label(dc, 14, 222, 452, 16, "", SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 机位总览
    ------------------------------------------------------------------
    local sc = theme.card(p, 16, 318, 500, 266)
    theme.label(sc, 14, 8, 200, 22, "机位总览", SZ.m, C.ink)
    ui.stand_note = theme.label(sc, 180, 8, 306, 22, "", SZ.xs, C.ink3, RT)

    for i, s in ipairs(sim.stands()) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local x = 14 + col * 118
        local y = 36 + row * 70
        local cell = theme.card(sc, x, y, 108, 62, {
            color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
            on_click = function()
                local f = sim.stand_flight(s.id)
                if f and alive then app.go("flight", f.idx) end
            end,
        })
        local id = theme.label(cell, 10, 6, 60, 20, s.id, SZ.s, C.ink2)
        local wide = theme.label(cell, 60, 8, 40, 16, s.wide and "宽体" or "窄体",
            SZ.xs, s.wide and C.amber or 0x445F7A, RT)
        local cs = theme.label(cell, 10, 28, 88, 18, "", SZ.xs, C.ink3)
        local st = theme.label(cell, 10, 44, 88, 16, "", SZ.xs, C.ink3)
        ui.stands[i] = { cell = cell, id = id, wide = wide, cs = cs, st = st, s = s }
    end
    theme.label(sc, 14, 246, 470, 14, "点击已占用机位可直接进入该航班保障详情",
        SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 关于
    ------------------------------------------------------------------
    local ac = theme.card(p, 528, 318, 480, 266)
    theme.label(ac, 14, 8, 240, 22, "关于 AeroDeck", SZ.m, C.ink)

    local logo = theme.card(ac, 14, 38, 56, 56, { color = 0x0B2231, radius = 14,
        border_color = C.line2, border_width = 1 })
    art.icon(logo, "radar", 12, 12, 32, C.cyan)
    theme.label(ac, 82, 40, 240, 26, conf.brand, SZ.l, C.ink)
    theme.label(ac, 82, 66, 300, 18, conf.name .. " v" .. conf.version, SZ.xs, C.ink3)
    theme.label(ac, 82, 84, 300, 18, "Air8607 · 10.1\" 1024x600 · 机坪夜航值守",
        SZ.xs, 0x445F7A)

    local tips = {
        "· 主页雷达上的每架飞机都可直接点开保障详情",
        "· 气象页调低能见度会立刻触发 LVP 与放行降级",
        "· 保障节点推进后，机位占用与准点率同步刷新",
        "· 结冰道面 + 低温会自动把在坪航班标为待除冰",
    }
    for i, t in ipairs(tips) do
        theme.label(ac, 14, 112 + (i - 1) * 20, 450, 18, t, SZ.xs, C.ink3)
    end

    theme.ghost(ac, 14, 202, 140, 34, "回机坪", {
        on_click = function() if alive then app.go("apron") end end,
    })
    theme.ghost(ac, 162, 202, 140, 34, "跑道气象", {
        on_click = function() if alive then app.go("weather") end end,
    })
    theme.ghost(ac, 310, 202, 156, 34, "查看首个航班", {
        on_click = function()
            if not alive then return end
            local list = sim.flights()
            for _, f in ipairs(list) do
                if not f.gone then app.go("flight", f.idx) return end
            end
            app.toast("当前没有在坪航班", C.gold)
        end,
    })

    ------------------------------------------------------------------
    -- 刷新
    ------------------------------------------------------------------
    local function fw_text()
        local v = "未知"
        if rtos and rtos.version then
            local ok, r = pcall(rtos.version)
            if ok and type(r) == "string" then v = r end
        end
        return v
    end
    local fw_cached = fw_text()

    function refresh()
        if not alive then return end

        local used, total = sim.res_sum()
        for _, it in ipairs(ui.res) do
            local avail = math.max(0, it.r.total - it.r.used)
            it.info:set_text(string.format("在役 %d / 总量 %d · 空闲 %d",
                it.r.used, it.r.total, avail))
            it.info:set_color(avail == 0 and C.red or C.ink3)
            it.bar.set(it.r.used / math.max(it.r.total, 1),
                avail == 0 and C.red or C.cyan)
            it.row:set_border_color(avail == 0 and C.red or C.line, 1)
        end
        ui.res_note:set_text(string.format("资源占用 %d/%d", used, total))

        ui.mode_note:set_text(sim.paused and "已暂停" or "自动推演中")
        ui.mode_note:set_color(sim.paused and C.gold or C.green)
        ui.pause_text:set_text(sim.paused and "继续演示" or "暂停演示")
        ui.pause_text:set_color(sim.paused and C.gold or C.ink)
        app.dot_paint(ui.pause_dot, 3, sim.paused and C.gold or C.green)

        ui.sys[1]:set_text(sim.uptime_text())
        ui.sys[2]:set_text((conf.sim.interval_ms / 1000) .. " 秒 / 次")
        ui.sys[3]:set_text(sim.on_stand() .. " 架次 · 机位 " ..
            sim.occupied() .. "/" .. sim.stand_total())
        ui.sys[4]:set_text(sim.alarm_count() .. " 条")
        ui.fw:set_text(string.format("固件 %s · Lua %s · 字号档 %d 档",
            fw_cached, tostring(_VERSION), 6))

        for _, it in ipairs(ui.stands) do
            local f = sim.stand_flight(it.s.id)
            if f then
                it.cs:set_text(f.cs)
                it.cs:set_color(C.ink)
                it.st:set_text(sim.status_text(f))
                it.st:set_color(f.deice and C.orange or C.ink3)
                it.cell:set_color(C.panel3)
                it.cell:set_border_color(f.deice and C.orange or C.line2, 1)
                it.id:set_color(C.ink)
            else
                it.cs:set_text("空闲")
                it.cs:set_color(C.green)
                it.st:set_text(it.s.wide and "可停宽体" or "可停窄体")
                it.st:set_color(0x445F7A)
                it.cell:set_color(C.panel2)
                it.cell:set_border_color(C.line, 1)
                it.id:set_color(C.ink2)
            end
        end
        ui.stand_note:set_text(string.format("占用 %d/%d", sim.occupied(), sim.stand_total()))
    end

    pcall(refresh)

    return {
        refresh = function() if alive and refresh then pcall(refresh) end end,
        tick_minute = function() if alive and ui.clock then ui.clock:set_text(sim.clock()) end end,
        destroy = function() alive = false end,
    }
end

return M
