-- page_crop.lua  页面2：作物监测（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(2, "作物监测", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "作物生长状态", "ic_seedling.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "环境监测数据", "ic_temp.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "土壤墒情", "ic_barchart.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "病虫害预警", "ic_bug.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "作物长势排行", "ic_trophy.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "实时告警", "ic_alarm.png")

    theme.donut(root, a1, "donut2.png", {
        { name = "苗期",   val = "18.5%", color = C.accent },
        { name = "生长期", val = "42.3%", color = C.pink },
        { name = "成熟期", val = "26.7%", color = C.yellow },
        { name = "采收期", val = "12.5%", color = C.blue },
    }, "1280", "种植面积(亩)")

    local m2 = theme.metrics(root, a2, {
        { name = "气温",  unit = "℃",    color = C.accent, icon = "ic_temp.png" },
        { name = "湿度",  unit = "%",     color = C.orange, icon = "ic_drop.png" },
        { name = "光照",  unit = "klux",  color = C.yellow, icon = "ic_sun.png" },
        { name = "CO2",  unit = "ppm",   color = C.cyan,   icon = "ic_leaf.png" },
    }, 2)

    local c3 = theme.chart(root, a3, { y_max = 100, ulabel = "墒情(%)",
        series = { { name = "土壤湿度", color = C.accent },
                   { name = "土壤温度", color = C.orange } } })

    local l4 = theme.list(root, a4, {
        "蚜虫风险(A区) - 中度", "霜霉风险(B区) - 低",
        "钻心虫(C区) - 已防治", "白粉病(D区) - 低",
    }, { C.yellow, C.sub, C.red, C.sub })

    local c5 = theme.chart(root, a5, { type = "bar", y_max = 100,
        ulabel = "长势(分)", color = C.accent,
        cats = { "A区", "B区", "C区", "D区", "E区", "F区" } })

    local l6 = theme.list(root, a6, {
        "B区湿度偏低", "C区光照过强", "3号传感器离线", "D区施肥延迟",
    }, { C.yellow, C.red, C.red, C.sub })

    return function()
        theme.set_metric(m2[1], mock.next("air_t", 18, 32))
        theme.set_metric(m2[2], mock.next("air_h", 40, 90))
        theme.set_metric(m2[3], mock.next("light", 20, 80))
        theme.set_metric(m2[4], mock.next("co2", 380, 900, 20), 0)

        theme.set_chart(c3, mock.series("sh2", 30, 78, 24, 55),
                            mock.series("st2", 12, 30, 24, 20))

        theme.set_val(l4[1], "09:47")
        theme.set_val(l4[2], "09:12")
        theme.set_val(l4[3], "昨日")
        theme.set_val(l4[4], "昨日")

        theme.set_chart(c5, mock.series("rank", 55, 95, 6, 85))

        theme.set_val(l6[1], mock.fmt(mock.next("w1", 25, 35)) .. "%")
        theme.set_val(l6[2], mock.rint("w2", 80, 95, 2) .. "klux")
        theme.set_val(l6[3], "今日 09:41")
        theme.set_val(l6[4], "预计 30min")
    end
end)