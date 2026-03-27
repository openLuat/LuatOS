--[[
@module chart_page
@summary 图表组件演示（折线图动态更新）
@version 1.0
@date 2026.03.09
@author 江访
@usage
本文件演示airui.chart组件的用法，展示折线图动态数据更新。
]]

local function ui_main()
    -- 初始化硬件


    -- 创建标题标签
    airui.label({
        text = "图表组件演示（动态折线图）",
        x = 10, y = 10, w = 300, h = 30,
        color = 0x000000,
        font_size = 18,
    })

    -- 创建折线图，Y轴范围0~100
    local chart = airui.chart({
        x = 20, y = 50,
        w = 280, h = 200,
        type = "line",
        y_min = 0, y_max = 100,   -- 整数范围
        point_count = 60,
        line_width = 2,
        point_radius = 0,
        legend = true,
        x_axis = { enable = true, ticks = 6, unit = "t" },
        y_axis = { enable = true, ticks = 6, unit = "%" },
    })

    -- 添加两个数据系列
    local sid_sin = chart:add_series({color = 0x00b4ff, name = "sin"})
    local sid_tri = chart:add_series({color = 0xff6b35, name = "tri"})

    -- 初始化数据（前20个点）
    local init_sin = {}
    local init_tri = {}
    for i = 1, 20 do
        local t = i * 0.5
        -- 映射到0~100的整数
        table.insert(init_sin, math.floor(50 + 50 * math.sin(t)))
        -- 三角波：0~100跳变
        table.insert(init_tri, (t % 4 < 2) and 90 or 10)
    end
    chart:set_values(sid_sin, init_sin)
    chart:set_values(sid_tri, init_tri)

    -- 动态更新循环
    local step = 0
    while true do
        step = step + 0.2
        -- 生成0~100的整数
        local val_sin = math.floor(50 + 50 * math.sin(step))
        local val_tri = (step % 4 < 2) and 90 or 10
        chart:push(sid_sin, val_sin)
        chart:push(sid_tri, val_tri)
        sys.wait(100)
    end
end

sys.taskInit(ui_main)