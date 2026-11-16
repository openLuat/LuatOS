-- page_env.lua  页面3：环境监测（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(3, "环境监测", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "当前天气", "ic_cloud.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "温度趋势", "ic_temp.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "湿度趋势", "ic_drop.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "光照与CO2", "ic_sun.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "土壤环境", "ic_grain.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "环境告警", "ic_alarm.png")

    local m1 = theme.metrics(root, a1, {
        { name = "温度", unit = "℃",   color = C.accent, icon = "ic_temp.png" },
        { name = "湿度", unit = "%",    color = C.orange, icon = "ic_drop.png" },
        { name = "风速", unit = "m/s",  color = C.yellow, icon = "ic_leaf.png" },
    }, 3)

    local c2 = theme.chart(root, a2, { y_max = 40, ulabel = "温度(℃)",
        color = C.accent, points = 24 })

    local c3 = theme.chart(root, a3, { y_max = 100, ulabel = "湿度(%)",
        color = C.cyan, points = 24 })

    local m4 = theme.metrics(root, a4, {
        { name = "光照", unit = "klux", color = C.yellow, icon = "ic_sun.png" },
        { name = "CO2", unit = "ppm",  color = C.cyan,   icon = "ic_leaf.png" },
    }, 2)

    local m5 = theme.metrics(root, a5, {
        { name = "土壤湿度", unit = "%", color = C.accent, icon = "ic_drop.png" },
        { name = "土壤温度", unit = "℃", color = C.orange, icon = "ic_temp.png" },
        { name = "pH值",    unit = "",  color = C.yellow, icon = "ic_flask.png" },
    }, 3)

    local l6 = theme.list(root, a6, {
        "光照过强(E区)", "CO2浓度偏高", "湿度偏低预警", "气温正常",
    }, { C.yellow, C.yellow, C.red, C.accent })

    return function()
        theme.set_metric(m1[1], mock.next("air_t", 18, 32))
        theme.set_metric(m1[2], mock.next("air_h", 40, 90))
        theme.set_metric(m1[3], mock.next("wind", 0.5, 8))

        theme.set_chart(c2, mock.series("trend_t", 18, 32, 24))
        theme.set_chart(c3, mock.series("trend_h", 40, 90, 24))

        theme.set_metric(m4[1], mock.next("light", 20, 80))
        theme.set_metric(m4[2], mock.next("co2", 380, 900, 20), 0)

        theme.set_metric(m5[1], mock.next("soil_h", 30, 75))
        theme.set_metric(m5[2], mock.next("soil_t", 15, 28))
        theme.set_metric(m5[3], mock.next("soil_ph", 5.5, 7.5))

        theme.set_val(l6[1], mock.rint("lx", 70, 85, 2) .. "klux")
        theme.set_val(l6[2], mock.rint("co2a", 850, 950, 10) .. "ppm")
        theme.set_val(l6[3], mock.fmt(mock.next("hwa", 25, 34)) .. "%")
        theme.set_val(l6[4], mock.fmt(mock.next("air_t", 18, 32)) .. "℃")
    end
end)