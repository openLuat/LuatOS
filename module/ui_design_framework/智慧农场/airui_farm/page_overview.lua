-- page_overview.lua  页面1：农场总览（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(1, "农场总览", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "农场基本信息", "ic_seedling.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "作物分布", "ic_grain.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "产量预测", "ic_chart.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "水肥监测", "ic_drop.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "土壤监测", "ic_flask.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "设备运行状态", "ic_pc.png")

    local m1 = theme.metrics(root, a1, {
        { name = "总面积",   unit = "亩", color = C.accent, icon = "ic_area.png" },
        { name = "种植面积", unit = "亩", color = C.orange, icon = "ic_seedling.png" },
        { name = "设备总数", unit = "台", color = C.yellow, icon = "ic_pc.png" },
        { name = "在线设备", unit = "台", color = C.cyan,   icon = "ic_signal.png" },
    }, 2)

    theme.donut(root, a2, "donut1.png", {
        { name = "水稻", val = "31.84%", color = C.accent },
        { name = "小麦", val = "11.53%", color = C.pink },
        { name = "玉米", val = "6.79%",  color = C.yellow },
        { name = "果树", val = "33.29%", color = C.blue },
        { name = "蔬菜", val = "16.75%", color = C.cyan },
    }, "5", "作物种类")

    local c3 = theme.chart(root, a3, { type = "bar", y_max = 50,
        ulabel = "产量(吨)",
        cats = { "水稻", "小麦", "玉米", "果树", "蔬菜" },
        series = { { name = "去年产量", color = C.orange },
                   { name = "预测产量", color = C.accent } } })

    local c4 = theme.chart(root, a4, { type = "bar", y_max = 100,
        cats = { "区域A", "区域B", "区域C", "区域D", "区域E", "区域F" },
        series = { { name = "水分", color = C.accent },
                   { name = "肥力", color = C.orange } } })

    local c5 = theme.chart(root, a5, { type = "bar", y_max = 600,
        ulabel = "含量/指数",
        cats = { "氮", "磷", "钾", "酸碱度", "有机质" },
        series = { { name = "实际值", color = C.accent },
                   { name = "标准值", color = C.blue } } })

    local l6 = theme.list(root, a6, {
        "土壤传感器", "气象站", "灌溉设备", "卷帘/风机",
    }, { C.sub, C.sub, C.sub, C.sub })

    return function()
        theme.set_metric(m1[1], 1215, 0)
        theme.set_metric(m1[2], 816, 0)
        theme.set_metric(m1[3], 40, 0)
        theme.set_metric(m1[4], mock.rint("ondev", 33, 40, 1), 0)

        theme.set_chart(c3, mock.series("cropL", 8, 44, 5, 22),
                            mock.series("cropP", 8, 46, 5, 25))
        theme.set_chart(c4, mock.series("wA", 40, 95, 6, 70),
                            mock.series("fA", 15, 90, 6, 45))
        theme.set_chart(c5, mock.series("sAct", 120, 560, 5, 300),
                            mock.series("sStd", 100, 520, 5, 260))

        theme.set_val(l6[1], mock.rint("s1", 33, 40, 1) .. "/40 在线")
        theme.set_val(l6[2], "运行中 2/2")
        theme.set_val(l6[3], "灌溉中 3/6")
        theme.set_val(l6[4], "开启 1/4")
    end
end)