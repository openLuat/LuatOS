--[[
@module chart_page
@summary 图表组件演示 (折线图)
@version 1.0
@date 2026.03.09
@author 江访
@usage
本文件演示airui.chart组件的用法，展示折线图、多系列数据。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建图表（折线图）
    local chart = airui.chart({
        x = 20,
        y = 20,
        w = 760,
        h = 440,
        type = "line",                -- 折线图
        y_min = 0,
        y_max = 100,
        point_count = 120,            -- 数据点总数
        update_mode = "shift",         -- 滚动更新
        line_color = 0x00b4ff,         -- 主系列颜色
        line_width = 2,
        point_radius = 2,              -- 显示数据点
        hdiv = 6,
        vdiv = 6,
        legend = true,                 -- 显示图例
        x_axis = { enable = true, min = 0, max = 120, ticks = 6, unit = "s" },
        y_axis = { enable = true, min = 0, max = 100, ticks = 6, unit = "%" }
    })

    -- 添加第二个系列
    local sid2 = chart:add_series({ color = 0xff6b35, name = "avg" })
    -- 添加第三个系列
    local sid3 = chart:add_series({ color = 0x22c55e, name = "diff" })
    -- 设置第一个系列名称
    chart:set_series_name(1, "raw")

    -- 设置初始数据
    chart:set_values(1, {50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70})
    chart:set_values(sid2, {50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60})
    chart:set_values(sid3, {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10})

    -- 模拟动态推送（可选）
    sys.timerLoopStart(function()
        -- 随机生成新数据并推入
        local v1 = 50 + math.random(-20, 20)
        local v2 = 50 + math.random(-15, 15)
        local v3 = v1 - v2
        chart:push(1, v1)
        chart:push(sid2, v2)
        chart:push(sid3, v3)
    end, 1000)
end

sys.taskInit(ui_main)