-- page_device.lua  页面5：智能设备（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(5, "智能设备", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "设备数据概览", "ic_signal.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "气象监测", "ic_cloud.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "设备状态监控", "ic_pc.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "设备负载", "ic_barchart.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "实时告警", "ic_alarm.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "作物生长监测", "ic_seedling.png")

    local m1 = theme.metrics(root, a1, {
        { name = "生产面积", unit = "亩", color = C.accent, icon = "ic_area.png" },
        { name = "作物种类", unit = "类", color = C.orange, icon = "ic_grain.png" },
        { name = "产量预测", unit = "吨", color = C.yellow, icon = "ic_chart.png" },
        { name = "设备总数", unit = "台", color = C.cyan,   icon = "ic_pc.png" },
    }, 2)

    local m2 = theme.metrics(root, a2, {
        { name = "温度", unit = "℃",   color = C.accent, icon = "ic_temp.png" },
        { name = "湿度", unit = "%",    color = C.orange, icon = "ic_drop.png" },
        { name = "降水", unit = "mm",   color = C.blue,   icon = "ic_rain.png" },
    }, 3)

    local l3 = theme.list(root, a3, {
        "土壤传感器", "气象站", "灌溉设备", "监控摄像头",
    }, { C.sub, C.sub, C.sub, C.sub })

    local c4 = theme.chart(root, a4, { type = "bar", y_max = 100,
        ulabel = "负载(%)", color = C.cyan,
        cats = { "水泵", "风机", "卷帘", "阀门", "传感器", "摄像头" } })

    local l5 = theme.list(root, a5, {
        "2号水泵电压波动", "5号传感器信号弱", "3号卷帘延迟响应", "气象站通信恢复",
    }, { C.yellow, C.red, C.yellow, C.accent })

    local c6 = theme.chart(root, a6, { y_max = 100, ulabel = "生长(cm)",
        color = C.accent, points = 24 })

    return function()
        theme.set_metric(m1[1], 1280, 0)
        theme.set_metric(m1[2], 12, 0)
        theme.set_metric(m1[3], mock.rint("prod", 320, 380, 1), 0)
        theme.set_metric(m1[4], 45, 0)

        theme.set_metric(m2[1], mock.next("air_t", 18, 32))
        theme.set_metric(m2[2], mock.next("air_h", 40, 90))
        theme.set_metric(m2[3], mock.rint("rain", 0, 25, 1), 0)

        theme.set_val(l3[1], "在线 18/20")
        theme.set_val(l3[2], "在线 2/2")
        theme.set_val(l3[3], "在线 12/15")
        theme.set_val(l3[4], "在线 10/10")

        theme.set_chart(c4, mock.series("devload", 20, 92, 6, 55))

        theme.set_val(l5[1], mock.rint("v1", 218, 235, 1) .. "V")
        theme.set_val(l5[2], "RSSI -92dBm")
        theme.set_val(l5[3], "延迟 2.3s")
        theme.set_val(l5[4], "正常")

        theme.set_chart(c6, mock.series("grow", 10, 95, 24, 55))
    end
end)