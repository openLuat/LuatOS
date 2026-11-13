-- page_trace.lua  页面8：质量追溯（与 preview.html 逐面板一致）
local sys   = require "sys"
local theme = require "theme"
local mock  = require "mock"

theme.make_page(8, "质量追溯", function(root, cx, cy, cw, ch)
    local C = theme.C

    local a1 = theme.panel(root, theme.cell(cx, cy, cw, ch, 1), "产品基本信息", "ic_tag.png")
    local a2 = theme.panel(root, theme.cell(cx, cy, cw, ch, 2), "质量指标", "ic_ok.png")
    local a3 = theme.panel(root, theme.cell(cx, cy, cw, ch, 3), "追溯次数统计", "ic_search.png")
    local a4 = theme.panel(root, theme.cell(cx, cy, cw, ch, 4), "质量等级分布", "ic_medal.png")
    local a5 = theme.panel(root, theme.cell(cx, cy, cw, ch, 5), "溯源链路", "ic_link.png")
    local a6 = theme.panel(root, theme.cell(cx, cy, cw, ch, 6), "认证与预警", "ic_shield.png")

    local m1 = theme.metrics(root, a1, {
        { name = "产地批次", unit = "个", color = C.accent, icon = "ic_tag.png" },
        { name = "种植面积", unit = "亩", color = C.orange, icon = "ic_area.png" },
        { name = "预计产量", unit = "吨", color = C.yellow, icon = "ic_chart.png" },
        { name = "合格率",   unit = "%",  color = C.cyan,   icon = "ic_ok.png" },
    }, 2)

    local l2 = theme.list(root, a2, {
        "农药残留检测", "重金属检测", "微生物检测", "新鲜度评级",
    }, { C.accent, C.accent, C.sub, C.yellow })

    local c3 = theme.chart(root, a3, { y_max = 200, ulabel = "追溯(次)",
        color = C.cyan, points = 24 })

    local c4 = theme.chart(root, a4, { type = "bar", y_max = 100,
        ulabel = "占比(%)", color = C.accent,
        cats = { "特级", "一级", "二级", "三级" } })

    local p5 = theme.progress(root, a5, {
        { name = "产地信息", pc = 100, color = C.accent },
        { name = "加工环节", pc = 100, color = C.cyan },
        { name = "物流运输", pc = 72,  color = C.blue },
        { name = "终端销售", pc = 45,  color = C.orange },
    })

    local l6 = theme.list(root, a6, {
        "绿色食品认证", "有机产品认证", "溯源码异常预警", "冷链温度预警",
    }, { C.accent, C.accent, C.yellow, C.red })

    return function()
        theme.set_metric(m1[1], 36, 0)
        theme.set_metric(m1[2], 1280, 0)
        theme.set_metric(m1[3], mock.rint("tprod", 400, 480, 1), 0)
        theme.set_metric(m1[4], mock.rint("pass", 96, 100, 1), 0)

        theme.set_val(l2[1], "未检出")
        theme.set_val(l2[2], "达标")
        theme.set_val(l2[3], "合格")
        theme.set_val(l2[4], mock.rint("fresh", 88, 96, 1) .. " 分")

        theme.set_chart(c3, mock.series("trace", 40, 180, 24, 110))

        theme.set_chart(c4, mock.series("grade", 30, 95, 4, 60))

        theme.set_progress(p5[1], 100)
        theme.set_progress(p5[2], 100)
        theme.set_progress(p5[3], mock.rint("logi", 68, 76, 1))
        theme.set_progress(p5[4], mock.rint("retail", 41, 49, 1))

        theme.set_val(l6[1], "有效期至 2027")
        theme.set_val(l6[2], "有效期至 2027")
        theme.set_val(l6[3], mock.rint("abn", 0, 3, 1) .. " 条")
        theme.set_val(l6[4], mock.rint("cold", 0, 2, 1) .. " 条")
    end
end)