-- page_market.lua  页面7：市场销售（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(7, "市场销售", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "销售概览", "ic_money.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "利润分析", "ic_barchart.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "销售趋势", "ic_chart.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "产品销售排行", "ic_trophy.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "产品类别分析", "ic_veg.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "季节性销售分析", "ic_season.png")

    local m1 = theme.metrics(root, a1, {
        { name = "总销售额", unit = "万元", color = C.accent, icon = "ic_money.png" },
        { name = "销售量",   unit = "吨",   color = C.orange, icon = "ic_box.png" },
        { name = "同比增长", unit = "%",    color = C.yellow, icon = "ic_chart.png" },
    }, 3)

    local p2 = theme.progress(root, a2, {
        { name = "毛利率", pc = 42, color = C.blue },
        { name = "净利率", pc = 31, color = C.red },
        { name = "复购率", pc = 58, color = C.pink },
        { name = "回款率", pc = 86, color = C.yellow },
        { name = "增长率", pc = 24, color = C.cyan },
    })

    local c3 = theme.chart(root, a3, { y_max = 100, ulabel = "销售额(万元)",
        series = { { name = "销售额", color = C.accent },
                   { name = "目标",   color = C.orange } } })

    local c4 = theme.chart(root, a4, { type = "bar", y_max = 80,
        ulabel = "销量(吨)", color = C.accent,
        cats = { "有机蔬菜", "优质水稻", "时令水果", "生态禽蛋", "干货", "杂粮" } })

    theme.donut(root, a5, "donut4.png", {
        { name = "蔬菜", val = "52%", color = C.accent },
        { name = "水果", val = "28%", color = C.pink },
        { name = "粮食", val = "20%", color = C.yellow },
    }, "12", "产品类别")

    local c6 = theme.chart(root, a6, { type = "bar", y_max = 100,
        ulabel = "占比(%)", color = C.orange,
        cats = { "春", "夏", "秋", "冬" } })

    return function()
        theme.set_metric(m1[1], mock.rint("sales", 680, 760, 1), 0)
        theme.set_metric(m1[2], mock.rint("svol", 950, 1100, 1), 0)
        theme.set_metric(m1[3], mock.rint("sgrow", 15, 32, 1), 0)

        theme.set_progress(p2[1], mock.rint("mp1", 40, 46, 1))
        theme.set_progress(p2[2], mock.rint("mp2", 28, 34, 1))
        theme.set_progress(p2[3], mock.rint("mp3", 54, 62, 1))
        theme.set_progress(p2[4], mock.rint("mp4", 82, 90, 1))
        theme.set_progress(p2[5], mock.rint("mp5", 20, 28, 1))

        theme.set_chart(c3, mock.series("sale_t", 40, 92, 24, 66),
                            mock.series("sale_g", 45, 88, 24, 62))
        theme.set_chart(c4, mock.series("rank4", 20, 78, 6, 48))
        theme.set_chart(c6, mock.series("season", 30, 95, 4, 62))
    end
end)