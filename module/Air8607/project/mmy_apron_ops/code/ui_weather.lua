--[[
@module  ui_weather
@summary AeroDeck 气象页：跑道风、能见度/RVR、跑道状态、趋势曲线与运行影响
@version 1.0
@date    2026.11.05
        本页所有调节都会立刻回灌 sim，主页 KPI / 告警 / 除冰需求随之变化。
]]
local conf = require "conf"
local theme = require "theme"
local art = require "art"
local sim = require "sim"
local app = require "app"

local C, SZ = theme.C, theme.SZ
local CT, RT = airui.TEXT_ALIGN_CENTER, airui.TEXT_ALIGN_RIGHT

local M = {}

-- 步进控件：返回 {update=function()}，按钮连续点也不会飘
local function stepper(parent, x, y, w, h, text, fn, color)
    return theme.ghost(parent, x, y, w, h, text, {
        border = color or C.line2,
        fg = color or C.ink,
        on_click = function() fn() end,
    })
end

function M.build(p)
    local alive = true
    local ui = { trend = 1 }
    local refresh, select_trend

    local _, clock = app.subbar(p, "跑道气象", "机坪指挥 · 气象与跑道状态", function()
        app.go("apron")
    end)
    ui.clock = clock

    ------------------------------------------------------------------
    -- 跑道风
    ------------------------------------------------------------------
    local wc = theme.card(p, 16, 66, 340, 232)
    theme.label(wc, 14, 8, 160, 22, "跑道风", SZ.m, C.ink)
    ui.wind_lv = theme.label(wc, 150, 8, 176, 22, "", SZ.xs, C.ink3, RT)

    ui.compass = art.compass(wc, 14, 36, 116, 0, C.cyan, 0x1D3A55)
    theme.label(wc, 140, 38, 186, 16, "风向 / 风速", SZ.xs, C.ink3)
    ui.wdir = theme.label(wc, 140, 52, 186, 28, "--", SZ.l, C.ink)
    ui.wspd = theme.label(wc, 140, 84, 186, 28, "--", SZ.l, C.cyan)
    ui.wdet = theme.label(wc, 140, 114, 186, 18, "", SZ.xs, C.ink3)
    ui.wsector = theme.chip(wc, 140, 136, 76, 20, "", C.ink2, C.panel2, SZ.xs)

    theme.label(wc, 16, 170, 40, 16, "风向", SZ.xs, C.ink3)
    -- 文案里的减号一律用 ASCII '-'（U+002D）。hzfont 字库没有 U+2212 数学减号，
    -- 用 '−' 会渲染成方框（'+' 是 ASCII，正常显示）。
    stepper(wc, 58, 162, 80, 30, "-15°", function()
        sim.set_wind_dir(sim.wx().wind_dir - 15)
        if refresh then refresh() end
    end, C.cyan)
    stepper(wc, 146, 162, 80, 30, "+15°", function()
        sim.set_wind_dir(sim.wx().wind_dir + 15)
        if refresh then refresh() end
    end, C.cyan)

    theme.label(wc, 16, 206, 40, 16, "风速", SZ.xs, C.ink3)
    stepper(wc, 58, 198, 80, 30, "-2 m/s", function()
        sim.set_wind(sim.wx().wind_spd - 2)
        if refresh then refresh() end
    end, C.amber)
    stepper(wc, 146, 198, 80, 30, "+2 m/s", function()
        sim.set_wind(sim.wx().wind_spd + 2)
        if refresh then refresh() end
    end, C.amber)

    ------------------------------------------------------------------
    -- 能见度 / RVR
    ------------------------------------------------------------------
    local vc = theme.card(p, 372, 66, 320, 232)
    theme.label(vc, 14, 8, 190, 22, "能见度 / 跑道视程", SZ.m, C.ink)
    ui.vis_lv = theme.label(vc, 200, 8, 106, 22, "", SZ.xs, C.ink3, RT)

    ui.vis = theme.label(vc, 14, 32, 150, 38, "--", SZ.xl, C.ink)
    theme.label(vc, 116, 44, 20, 20, "m", SZ.s, C.ink3)
    ui.vis_note = theme.label(vc, 150, 40, 156, 18, "", SZ.xs, C.ink3, RT)
    ui.vis_bar = theme.segbar(vc, 14, 76, 292, 8, 24, C.cyan, 0x16283C, 2)

    theme.label(vc, 14, 96, 200, 16, "跑道视程 RVR", SZ.xs, C.ink3)
    ui.rvr = theme.label(vc, 14, 112, 150, 28, "--", SZ.l, C.ink)
    ui.rvr_note = theme.label(vc, 150, 118, 156, 18, "", SZ.xs, C.ink3, RT)
    ui.rvr_bar = theme.segbar(vc, 14, 146, 292, 8, 24, C.amber, 0x16283C, 2)

    stepper(vc, 14, 172, 84, 32, "-500m", function()
        sim.set_vis(sim.wx().vis - 500)
        if refresh then refresh() end
    end, C.cyan)
    stepper(vc, 106, 172, 84, 32, "+500m", function()
        sim.set_vis(sim.wx().vis + 500)
        if refresh then refresh() end
    end, C.cyan)
    stepper(vc, 198, 172, 108, 32, "LVP 800m", function()
        sim.set_vis(760)
        app.toast("能见度已设为 LVP 门限", C.red)
        if refresh then refresh() end
    end, C.red)
    theme.label(vc, 14, 208, 292, 16, "门限：能见度 800m / RVR 550m", SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 跑道状态
    ------------------------------------------------------------------
    local sc = theme.card(p, 708, 66, 300, 232)
    theme.label(sc, 14, 8, 160, 22, "跑道状态", SZ.m, C.ink)
    ui.mu = theme.label(sc, 200, 8, 86, 22, "", SZ.xs, C.ink3, RT)

    ui.state_cells = {}
    for i, s in ipairs(conf.wx.states) do
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        local cell = theme.card(sc, 14 + col * 142, 34 + row * 60, 132, 54, {
            color = C.panel2, radius = 9, border_color = C.line, border_width = 1,
            on_click = function()
                if not alive then return end
                local ok = sim.set_state(s.key)
                if ok then app.toast("跑道状态：" .. s.name, C.amber) end
                if refresh then refresh() end
            end,
        })
        local name = theme.label(cell, 12, 8, 108, 20, s.name, SZ.s, C.ink2)
        local mu = theme.label(cell, 12, 30, 108, 16,
            string.format("μ %.2f", s.mu), SZ.xs, C.ink3)
        ui.state_cells[i] = { cell = cell, name = name, mu = mu, s = s }
    end

    ui.deice_note = theme.label(sc, 14, 156, 272, 18, "", SZ.xs, C.ink3)
    ui.temp_note = theme.label(sc, 14, 176, 272, 18, "", SZ.xs, C.ink3)
    theme.label(sc, 14, 200, 272, 16, "提示：点上方色块切换道面状态", SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 趋势曲线
    ------------------------------------------------------------------
    local tdefs = {
        { key = "vis",  name = "能见度", unit = "m",   color = C.cyan,
          min = conf.wx.vis.min, max = conf.wx.vis.max, lo = conf.wx.vis.lo },
        { key = "wind", name = "风速",   unit = "m/s", color = C.amber,
          min = 0, max = conf.wx.wind.max, lo = conf.wx.wind.lo },
        { key = "temp", name = "温度",   unit = "℃",  color = C.violet,
          min = conf.wx.temp.min, max = conf.wx.temp.max, lo = conf.wx.temp.lo },
    }

    local tc = theme.card(p, 16, 310, 600, 274)
    theme.label(tc, 14, 8, 180, 22, "气象趋势", SZ.m, C.ink)
    ui.trend_note = theme.label(tc, 180, 8, 130, 22, "", SZ.xs, C.ink3, RT)

    ui.tchips = {}
    for i, d in ipairs(tdefs) do
        local ch = theme.chip(tc, 322 + (i - 1) * 88, 8, 80, 24, d.name, C.ink3, C.panel2, SZ.xs)
        ui.tchips[i] = ch
        ch.box:set_color(C.panel2)
        ch.box:set_border_color(C.line, 1)
        -- 胶囊本身不带点击回调，用透明热区盖在上面接管触摸
        ch.hot = theme.card(tc, 322 + (i - 1) * 88, 8, 80, 24, {
            color = 0x000000, radius = 12, opacity = 0,
            on_click = function()
                if alive and select_trend then select_trend(i) end
            end,
        })
    end

    ui.wave = theme.shape(tc, 16, 44, 568, 146, {})

    ui.stats = {}
    for i = 1, 3 do
        local x = 16 + (i - 1) * 190
        local lb = theme.label(tc, x, 198, 90, 16, "", SZ.xs, C.ink3)
        local val = theme.label(tc, x, 214, 170, 26, "--", SZ.l, C.ink)
        ui.stats[i] = { name = lb, val = val }
    end
    theme.label(tc, 16, 246, 560, 16,
        "每格 2 分钟采样 · 保留 48 点 · 绿色带为该参数的正常区间", SZ.xs, 0x445F7A)

    ------------------------------------------------------------------
    -- 运行影响
    ------------------------------------------------------------------
    local ic = theme.card(p, 632, 310, 376, 274)
    theme.label(ic, 14, 8, 180, 22, "运行影响", SZ.m, C.ink)
    ui.lvp_chip = theme.chip(ic, 264, 8, 96, 22, "", C.ink2, C.panel2, SZ.xs)

    ui.impacts = {}
    local idefs = { "低能见运行", "建议跑道方向", "放行能力", "除冰需求" }
    for i, n in ipairs(idefs) do
        local y = 38 + (i - 1) * 26
        theme.label(ic, 14, y, 140, 20, n, SZ.xs, C.ink3)
        ui.impacts[i] = theme.label(ic, 154, y, 206, 20, "--", SZ.s, C.ink, RT)
    end

    theme.label(ic, 14, 146, 200, 20, "处置建议", SZ.s, C.ink2)
    ui.adv1 = theme.label(ic, 14, 168, 348, 18, "", SZ.xs, C.ink3)
    ui.adv2 = theme.label(ic, 14, 188, 348, 18, "", SZ.xs, C.ink3)
    ui.adv3 = theme.label(ic, 14, 208, 348, 18, "", SZ.xs, C.ink3)

    theme.ghost(ic, 14, 234, 168, 30, "恢复默认气象", {
        on_click = function()
            if not alive then return end
            sim.set_wind(6.4)
            sim.set_wind_dir(22)
            sim.set_vis(2600)
            sim.set_temp(3.6)
            sim.set_state("dry")
            app.toast("气象参数已恢复为初始值", C.green)
            if refresh then refresh() end
        end,
    })
    theme.ghost(ic, 192, 234, 170, 30, "去设置页", {
        on_click = function() if alive then app.go("settings") end end,
    })

    ------------------------------------------------------------------
    -- 趋势切换
    ------------------------------------------------------------------
    function select_trend(i)
        ui.trend = i
        for k, ch in ipairs(ui.tchips) do
            if k == i then
                ch.set(tdefs[k].name, C.cyan)
                ch.box:set_color(0x0B2A38)
                ch.box:set_border_color(C.cyan, 1)
            else
                ch.set(tdefs[k].name, C.ink3)
                ch.box:set_color(C.panel2)
                ch.box:set_border_color(C.line, 1)
            end
        end
        ui.trend_note:set_text(tdefs[i].name .. " · " .. tdefs[i].unit)
        if refresh then refresh() end
    end

    ------------------------------------------------------------------
    -- 刷新
    ------------------------------------------------------------------
    function refresh()
        if not alive then return end
        local w = sim.wx()

        -- 风
        ui.compass:set_items(art.compass_items(116, w.wind_dir, C.cyan, 0x1D3A55))
        ui.wdir:set_text(string.format("%03d°", math.floor(w.wind_dir)))
        ui.wspd:set_text(string.format("%.1f m/s", w.wind_spd))
        ui.wspd:set_color(w.wind_spd > conf.wx.wind.lo and C.red or
            (w.wind_spd > conf.wx.wind.hi and C.gold or C.cyan))
        ui.wdet:set_text(string.format("阵风 %.1f · 侧风 %.1f m/s", w.gust, sim.crosswind()))
        ui.wsector.set(sim.wind_sector(), C.ink2)
        local wl = w.wind_spd > conf.wx.wind.lo and "强侧风" or
            (w.wind_spd > conf.wx.wind.hi and "风力偏大" or "风力正常")
        ui.wind_lv:set_text(wl)
        ui.wind_lv:set_color(w.wind_spd > conf.wx.wind.lo and C.red or
            (w.wind_spd > conf.wx.wind.hi and C.gold or C.ink3))

        -- 能见度
        ui.vis:set_text(tostring(w.vis))
        ui.vis:set_color(w.vis < conf.wx.vis.lo and C.red or
            (w.vis < conf.wx.vis.hi and C.gold or C.ink))
        ui.vis_note:set_text(w.vis < conf.wx.vis.lo and "低于 LVP 门限" or
            (w.vis < conf.wx.vis.hi and "接近门限" or "能见度良好"))
        ui.vis_note:set_color(w.vis < conf.wx.vis.lo and C.red or
            (w.vis < conf.wx.vis.hi and C.gold or C.ink3))
        ui.vis_bar.set((w.vis - conf.wx.vis.min) / (conf.wx.vis.max - conf.wx.vis.min),
            w.vis < conf.wx.vis.lo and C.red or (w.vis < conf.wx.vis.hi and C.gold or C.cyan))

        ui.rvr:set_text(w.rvr .. " m")
        ui.rvr_note:set_text(w.rvr < conf.wx.rvr.lo and "不足着陆标准" or
            (w.rvr < conf.wx.rvr.hi and "接近标准" or "标准内"))
        ui.rvr_note:set_color(w.rvr < conf.wx.rvr.lo and C.red or
            (w.rvr < conf.wx.rvr.hi and C.gold or C.ink3))
        ui.rvr_bar.set((w.rvr - conf.wx.rvr.min) / (conf.wx.rvr.max - conf.wx.rvr.min),
            w.rvr < conf.wx.rvr.lo and C.red or C.amber)

        -- 跑道状态
        for _, it in ipairs(ui.state_cells) do
            if it.s.key == w.state then
                it.cell:set_color(0x0B2A38)
                it.cell:set_border_color(C.cyan, 1)
                it.name:set_color(C.cyan)
                it.mu:set_color(C.ink2)
            else
                it.cell:set_color(C.panel2)
                it.cell:set_border_color(C.line, 1)
                it.name:set_color(C.ink2)
                it.mu:set_color(C.ink3)
            end
        end
        ui.mu:set_text(string.format("μ %.2f", sim.mu()))
        local car = sim.res("deice")
        ui.deice_note:set_text(string.format("待除冰 %d 架 · 除冰车 %d/%d 可用",
            sim.deice_count(), math.max(0, car.total - car.used), car.total))
        ui.deice_note:set_color(sim.deice_count() > 0 and C.orange or C.ink3)
        ui.temp_note:set_text(string.format("机坪温度 %.1f ℃ · 露点 %.1f ℃ · 霜点风险%s",
            w.temp, w.dew, w.temp < conf.wx.temp.lo and "高" or "低"))
        ui.temp_note:set_color(w.temp < conf.wx.temp.lo and C.cyan or C.ink3)

        -- 趋势
        local d = tdefs[ui.trend]
        local h = sim.hist(d.key)
        local mn, mx, cur = 0, 0, 0
        if #h > 0 then
            mn, mx, cur = h[1], h[1], h[#h]
            for _, v in ipairs(h) do
                if v < mn then mn = v end
                if v > mx then mx = v end
            end
        end
        local pad = math.max((mx - mn) * 0.18, 1)
        pcall(function()
            ui.wave:set_items(art.waveform_items(568, 146, h, {
                color = d.color,
                min = mn - pad, max = mx + pad,
                lo = d.lo, hi = d.lo * 3, band = (ui.trend == 1),
                grid = 4,
            }))
        end)
        ui.stats[1].name:set_text("当前")
        ui.stats[1].val:set_text(string.format("%.0f %s", cur, d.unit))
        ui.stats[1].val:set_color(d.color)
        ui.stats[2].name:set_text("区间最低")
        ui.stats[2].val:set_text(string.format("%.0f %s", mn, d.unit))
        ui.stats[3].name:set_text("区间最高")
        ui.stats[3].val:set_text(string.format("%.0f %s", mx, d.unit))

        -- 运行影响
        local lvp = sim.lvp()
        ui.lvp_chip.set(lvp and "LVP 生效" or "常规运行", lvp and C.red or C.green)
        ui.lvp_chip.box:set_border_color(lvp and C.red or C.line, 1)

        ui.impacts[1]:set_text(lvp and "已启动" or "未启动")
        ui.impacts[1]:set_color(lvp and C.red or C.green)
        ui.impacts[2]:set_text(sim.headwind() >= 0 and "18L（顶风）" or "36R（顶风）")
        local cap = 36
        if w.vis < conf.wx.vis.lo then cap = 14
        elseif w.vis < conf.wx.vis.hi then cap = 24 end
        if w.wind_spd > conf.wx.wind.lo then cap = math.floor(cap * 0.7) end
        if sim.mu() < 0.3 then cap = math.floor(cap * 0.8) end
        ui.impacts[3]:set_text(cap .. " 架次/时")
        ui.impacts[3]:set_color(cap < 20 and C.gold or C.ink)
        ui.impacts[4]:set_text(sim.deice_count() .. " 架待除")
        ui.impacts[4]:set_color(sim.deice_count() > 0 and C.orange or C.ink)

        local a1, a2, a3, ac
        if w.vis < conf.wx.vis.lo then
            a1 = "· 启动低能见运行，放行间隔调整为 4 分钟"
            a2 = "· 加强跑道灯与滑行道边灯巡视"
            a3 = "· 除冰坪双通道开放，优先保障宽体机"
            ac = C.red
        elseif w.wind_spd > conf.wx.wind.lo then
            a1 = "· 侧风超限，宽体机改由 36R 起降"
            a2 = "· 廊桥作业暂停，改用车载客梯"
            a3 = "· 加强无动力设备系留检查"
            ac = C.gold
        elseif w.temp < conf.wx.temp.lo then
            a1 = "· 机翼霜冻风险升高，出港前逐架检查"
            a2 = "· 除冰液按 Type I / Type IV 配比供应"
            a3 = "· 缩短远机位摆渡间隔，减少旅客露天等待"
            ac = C.cyan
        else
            a1 = "· 气象条件良好，维持常规运行"
            a2 = "· 按计划推进保障节点，关注准点率"
            a3 = "· 下一轮例行观测 30 分钟后"
            ac = C.ink3
        end
        ui.adv1:set_text(a1)
        ui.adv2:set_text(a2)
        ui.adv3:set_text(a3)
        ui.adv1:set_color(ac)
        ui.adv2:set_color(ac)
        ui.adv3:set_color(ac)
    end

    select_trend(1)

    return {
        refresh = function() if alive and refresh then pcall(refresh) end end,
        tick_minute = function() if alive and ui.clock then ui.clock:set_text(sim.clock()) end end,
        destroy = function() alive = false end,
    }
end

return M
