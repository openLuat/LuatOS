-- page_operation.lua  页面6：生产运营（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(6, "生产运营", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "生产概览", "ic_factory.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "资源使用情况", "ic_box.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "月度产量分析", "ic_chart.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "成本构成", "ic_money.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "种植日历", "ic_calendar.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "市场价格趋势", "ic_trend.png")

    local m1 = theme.metrics(root, a1, {
        { name = "种植面积", unit = "亩", color = C.accent, icon = "ic_area.png" },
        { name = "品种数",   unit = "类", color = C.orange, icon = "ic_grain.png" },
        { name = "产量总计", unit = "吨", color = C.yellow, icon = "ic_chart.png" },
    }, 3)

    local m2 = theme.metrics(root, a2, {
        { name = "水",   unit = "m3", color = C.blue,   icon = "ic_drop.png" },
        { name = "肥",   unit = "kg", color = C.orange, icon = "ic_flask.png" },
        { name = "农药", unit = "kg", color = C.pink,   icon = "ic_shield.png" },
    }, 3)

    local c3 = theme.chart(root, a3, { type = "bar", y_max = 120,
        ulabel = "产量(吨)",
        cats = { "1月", "2月", "3月", "4月", "5月", "6月",
                 "7月", "8月", "9月", "10月", "11月", "12月" },
        series = { { name = "今年", color = C.accent },
                   { name = "去年", color = C.orange } } })

    local c4 = theme.chart(root, a4, { type = "bar", y_max = 50,
        ulabel = "成本(万元)", color = C.orange,
        cats = { "人工", "物料", "设备", "其他" } })

    local l5 = theme.list(root, a5, {
        "水稻 - 分蘖期", "小麦 - 拔节期", "玉米 - 播种期", "蔬菜 - 采收期",
    }, { C.sub, C.sub, C.accent, C.yellow })

    local c6 = theme.chart(root, a6, { y_max = 150, ulabel = "价格指数",
        color = C.purple, points = 24 })

    return function()
        theme.set_metric(m1[1], 1280, 0)
        theme.set_metric(m1[2], 12, 0)
        theme.set_metric(m1[3], mock.rint("prod6", 380, 460, 1), 0)

        theme.set_metric(m2[1], mock.rint("water6", 1200, 1800, 10), 0)
        theme.set_metric(m2[2], mock.rint("fert6", 300, 500, 10), 0)
        theme.set_metric(m2[3], mock.rint("pest6", 60, 120, 5), 0)

        theme.set_chart(c3, mock.series("m6a", 30, 110, 12, 65),
                            mock.series("m6b", 25, 100, 12, 55))
        theme.set_chart(c4, mock.series("cost", 8, 42, 4, 22))

        theme.set_val(l5[1], "第 185 天")
        theme.set_val(l5[2], "第 142 天")
        theme.set_val(l5[3], "第 12 天")
        theme.set_val(l5[4], "第 58 天")

        theme.set_chart(c6, mock.series("price", 80, 145, 24, 110))
    end
end)