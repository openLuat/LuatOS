-- page_resource.lua  页面4：资源优化（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(4, "资源优化", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "资源利用概览", "ic_recycle.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "资源消耗趋势", "ic_chart.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "土壤营养监测", "ic_flask.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "灌溉系统状态", "ic_drop.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "资源优化指标", "ic_target.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "系统告警信息", "ic_alarm.png")

    local m1 = theme.metrics(root, a1, {
        { name = "水资源利用率", unit = "%", color = C.accent, icon = "ic_drop.png" },
        { name = "肥料利用率",   unit = "%", color = C.orange, icon = "ic_flask.png" },
        { name = "能源利用率",   unit = "%", color = C.yellow, icon = "ic_bulb.png" },
    }, 3)

    local c2 = theme.chart(root, a2, { y_max = 100, ulabel = "消耗量",
        cats = { "1月", "2月", "3月", "4月", "5月", "6月",
                 "7月", "8月", "9月", "10月", "11月", "12月" },
        series = { { name = "用水量",   color = C.accent },
                   { name = "肥料用量", color = C.orange },
                   { name = "能源消耗", color = C.purple } } })

    theme.radar(root, a3, {
        { name = "氮含量", color = C.accent },
        { name = "磷含量", color = C.mint2 },
        { name = "钾含量", color = C.orange },
        { name = "有机质", color = C.pink },
    })

    theme.donut(root, a4, "donut3.png", {
        { name = "滴灌系统", val = "68", color = C.pink },
        { name = "喷灌系统", val = "99", color = C.accent },
        { name = "微喷系统", val = "34", color = C.orange },
        { name = "传统灌溉", val = "51", color = C.blue },
    }, "252", "灌溉系统状态")

    local p5 = theme.progress(root, a5, {
        { name = "智能灌溉",   pc = 78, color = C.blue },
        { name = "能源管理",   pc = 64, color = C.red },
        { name = "作物产量",   pc = 53, color = C.pink },
        { name = "病虫害防治", pc = 41, color = C.yellow },
        { name = "精准施肥",   pc = 29, color = C.cyan },
    })

    local l6 = theme.list(root, a6, {
        "肥料库存不足，建议及时补充", "检测到6号农田氮含量偏高",
        "智能监测系统检测到异常风速", "3号水泵压力波动异常",
    }, { C.sub, C.sub, C.sub, C.sub })

    return function()
        theme.set_metric(m1[1], mock.rint("wr", 84, 92, 1), 0)
        theme.set_metric(m1[2], mock.rint("fr", 88, 95, 1), 0)
        theme.set_metric(m1[3], mock.rint("er", 74, 84, 1), 0)

        theme.set_chart(c2, mock.series("wuse", 30, 95, 12, 60),
                            mock.series("fuse", 20, 90, 12, 50),
                            mock.series("euse", 25, 85, 12, 55))

        theme.set_progress(p5[1], mock.rint("pi1", 74, 82, 1))
        theme.set_progress(p5[2], mock.rint("pi2", 60, 68, 1))
        theme.set_progress(p5[3], mock.rint("pi3", 49, 57, 1))
        theme.set_progress(p5[4], mock.rint("pi4", 37, 45, 1))
        theme.set_progress(p5[5], mock.rint("pi5", 25, 33, 1))

        theme.set_val(l6[1], "09:47")
        theme.set_val(l6[2], "09:15")
        theme.set_val(l6[3], "30分钟前")
        theme.set_val(l6[4], "08:52")
    end
end)