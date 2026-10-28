--[[
@module  ui_settings
@summary ReefOS 设置页：设备管理、演示控制、参数体检与关于信息
@version 1.0
@date    2026.10.27
]]
local conf = require "conf"
local theme = require "theme"
local art = require "art"
local sim = require "sim"
local app = require "app"

local C, SZ = theme.C, theme.SZ
local RT = airui.TEXT_ALIGN_RIGHT

local M = {}

-- 缸龄：按 conf.tank.start（"2024.03"）与当前月份计算
local function age_text()
    local y, m = string.match(conf.tank.start or "", "(%d+)%.(%d+)")
    if not y then return "—" end
    local t = os.date("*t")
    local months = (t.year - tonumber(y)) * 12 + (t.month - tonumber(m))
    if months < 0 then months = 0 end
    if months < 12 then return months .. " 个月" end
    return string.format("%d 年 %d 个月", math.floor(months / 12), months % 12)
end

local function uptime_text()
    local min = sim.sim_min or 0
    if min < 60 then return min .. " 分钟" end
    return string.format("%.1f 小时", min / 60)
end

function M.build(p)
    local alive = true
    local ui = { dev = {}, vital = {} }
    local refresh_all

    local bar, clock, date = app.subbar(p, "系统设置", "设备管理 · 演示控制 · 关于")

    ------------------------------------------------------------------
    -- 设备管理
    ------------------------------------------------------------------
    local dc = theme.card(p, 16, 66, 560, 300)
    theme.label(dc, 16, 10, 160, 22, "设备管理", SZ.m, C.ink)
    ui.dev_sum = theme.label(dc, 16, 10, 560 - 32, 22, "", SZ.xs, C.ink3, RT)

    local keys = sim.devices()
    for i, key in ipairs(keys) do
        local d = sim.device(key)
        local y = 42 + (i - 1) * 40
        local row = {}
        row.card = theme.card(dc, 16, y, 528, 36, {
            color = C.panel2, radius = 8, border_color = C.line, border_width = 1,
            on_click = function()
                if not alive then return end
                sim.toggle_device(key)
                refresh_all()
            end,
        })
        row.icon = art.icon(row.card, d.icon, 10, 9, 18, C.ink3)
        theme.label(row.card, 38, 8, 110, 20, d.name, SZ.s, C.ink)
        theme.label(row.card, 152, 10, 230, 18, d.note or "", SZ.xs, C.ink3)
        row.chip = theme.chip(row.card, 450, 7, 62, 22, "关闭", C.ink3, C.panel3, SZ.xs)
        ui.dev[i] = { key = key, row = row }
    end

    ------------------------------------------------------------------
    -- 演示控制
    ------------------------------------------------------------------
    local mc = theme.card(p, 16, 378, 560, 206)
    theme.label(mc, 16, 10, 160, 22, "演示控制", SZ.m, C.ink)
    theme.label(mc, 16, 10, 560 - 32, 22, "数据由本地物理模型生成", SZ.xs, C.ink3, RT)

    local pw = theme.card(mc, 16, 40, 180, 56, {
        color = C.panel2, radius = 10, border_color = C.line, border_width = 1,
        on_click = function()
            if not alive then return end
            sim.paused = not sim.paused
            sim.log_event(sim.paused and "水质演示已暂停" or "水质演示已恢复", "warn")
            refresh_all()
        end,
    })
    ui.pw_dot = app.dot(pw, 16, 24, 6, C.green)
    ui.pw_text = theme.label(pw, 34, 15, 130, 26, "运行中", SZ.m, C.ink)
    theme.label(mc, 212, 44, 330, 20, "暂停后水质与水色停止演化，鱼群动画继续播放，", SZ.xs, C.ink2)
    theme.label(mc, 212, 64, 330, 20, "方便截图与讲解；恢复后模型从当前值继续推演。", SZ.xs, C.ink2)

    local btns = {
        { text = "补水 2L",  color = C.cyan,  fn = function() return sim.topup() end },
        { text = "换水 10%", color = C.blue,  fn = function() return sim.water_change() end },
        { text = "投喂",     color = C.coral, fn = function() return sim.feed() end },
    }
    for i, b in ipairs(btns) do
        theme.ghost(mc, 16 + (i - 1) * 178, 112, 166, 38, b.text, {
            size = SZ.s,
            on_click = function()
                if not alive then return end
                local msg = b.fn()
                if msg then app.toast(msg, b.color) end
                refresh_all()
            end,
        })
    end

    theme.ghost(mc, 16, 158, 166, 34, "重置演示数据", {
        size = SZ.xs,
        on_click = function()
            if not alive then return end
            sim.init()
            app.toast("演示数据已重置", C.gold)
            refresh_all()
        end,
    })
    ui.feed_info = theme.label(mc, 196, 160, 346, 18, "", SZ.xs, C.ink3)
    ui.water_info = theme.label(mc, 196, 178, 346, 18, "", SZ.xs, C.ink3)

    ------------------------------------------------------------------
    -- 参数体检
    ------------------------------------------------------------------
    local vc = theme.card(p, 592, 66, 416, 250)
    theme.label(vc, 16, 10, 200, 22, "参数体检", SZ.m, C.ink)
    ui.vital_sum = theme.label(vc, 16, 10, 416 - 32, 22, "", SZ.xs, C.green, RT)

    local mkeys = sim.keys()
    for i, key in ipairs(mkeys) do
        local col = math.floor((i - 1) / 4)
        local row = (i - 1) % 4
        local x = 16 + col * 196
        local y = 44 + row * 46
        local def = sim.def(key)
        local it = {}
        it.name = theme.label(vc, x, y, 90, 18, def.name, SZ.xs, C.ink3)
        it.value = theme.label(vc, x, y + 18, 120, 22, "--", SZ.m, C.ink)
        it.dot = app.dot(vc, x + 158, y + 24, 4, C.green)
        ui.vital[i] = { key = key, it = it }
    end

    ------------------------------------------------------------------
    -- 关于
    ------------------------------------------------------------------
    local ac = theme.card(p, 592, 328, 416, 256)
    theme.label(ac, 16, 14, 200, 30, "REEFOS", SZ.xl, C.cyan)
    theme.label(ac, 16, 50, 340, 18, conf.slogan, SZ.xs, C.ink3)
    theme.hline(ac, 16, 78, 384, C.line)

    local rows = {
        { "固件版本", conf.version },
        { "硬件平台", "Air8607 · Air1603" },
        { "显示屏", "10.1 英寸 RGB 1024 × 600" },
        { "缸体", conf.tank.name .. " · " .. conf.tank.volume .. " L" },
        { "开缸时间", conf.tank.start .. "（" .. age_text() .. "）" },
        { "模型运行", uptime_text() },
    }
    for i, r in ipairs(rows) do
        local y = 88 + (i - 1) * 24
        theme.label(ac, 16, y, 100, 18, r[1], SZ.xs, C.ink3)
        theme.label(ac, 116, y, 284, 18, r[2], SZ.xs, C.ink2, RT)
    end
    theme.label(ac, 16, 238, 384, 16, "无外接传感器：水质数据来自本地物理模型，仅用于交互演示。",
        SZ.xs, C.ink3)

    ------------------------------------------------------------------
    -- 刷新
    ------------------------------------------------------------------
    function refresh_all()
        if not alive then return end

        local on = sim.on_count()
        ui.dev_sum:set_text(on .. " / " .. #keys .. " 开启 · 当前 " .. sim.power() .. " W")
        for _, it in ipairs(ui.dev) do
            local d = sim.device(it.key)
            local c = d.on and C.cyan or C.ink3
            it.row.chip.set(d.on and "开启" or "关闭", c)
            it.row.card:set_border_color(d.on and C.line2 or C.line, 1)
            it.row.icon:set_items(art.icon_items(d.icon, 18, c))
        end

        app.dot_paint(ui.pw_dot, 6, sim.paused and C.gold or C.green)
        ui.pw_text:set_text(sim.paused and "已暂停" or "运行中")
        ui.pw_text:set_color(sim.paused and C.gold or C.ink)

        ui.feed_info:set_text("今日投喂 " .. sim.feed_count() .. " 次 · 上次 "
            .. sim.ago_text(sim.last_feed_ago_min()))
        ui.water_info:set_text("建议换水倒计时 " .. sim.remain_text(sim.water_remain_min()))

        local bad = sim.abnormal_count()
        local worst = sim.worst_level()
        ui.vital_sum:set_text(bad == 0 and "全部正常" or (bad .. " 项需关注"))
        ui.vital_sum:set_color(theme.state_color(worst))

        for _, it in ipairs(ui.vital) do
            local lv = sim.level(it.key)
            local col = theme.state_color(lv)
            it.it.value:set_text(sim.fmt(it.key, sim.value(it.key)) ..
                (sim.def(it.key).unit ~= "" and (" " .. sim.def(it.key).unit) or ""))
            it.it.value:set_color(lv == "ok" and C.ink or col)
            app.dot_paint(it.it.dot, 4, col)
        end
    end

    refresh_all()

    return {
        refresh = function()
            if not alive then return end
            clock:set_text(sim.clock())
            date:set_text(sim.date_text())
            refresh_all()
        end,
        destroy = function()
            alive = false
        end,
    }
end

return M
