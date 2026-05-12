--[[
@module shape_page
@summary 形状组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.shape组件的用法，展示直线、圆形、椭圆、矩形/圆角矩形等多种图元绘制。
]]

local function ui_main()
    -- 初始化硬件

    -- 创建主容器
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 800,
        h = 480,
        color = 0x1a1a2e,
    })

    -- 标题
    airui.label({
        parent = main_container,
        text = "Shape 形状组件演示",
        x = 0,
        y = 10,
        w = 800,
        h = 30,
        font_size = 24,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 示例1：直线（含虚线、圆头）
    airui.shape({
        parent = main_container,
        x = 20, y = 50, w = 760, h = 40,
        items = {
            {type = "line", x1 = 40, y1 = 20, x2 = 240, y2 = 20,
             color = 0xff3b30, width = 2},
            {type = "line", x1 = 280, y1 = 20, x2 = 480, y2 = 20,
             color = 0x22c55e, width = 6,
             round_start = true, round_end = true},
            {type = "line", x1 = 520, y1 = 20, x2 = 720, y2 = 20,
             color = 0x38bdf8, width = 2,
             dash_width = 8, dash_gap = 6},
        },
    })

    -- 示例2：圆形（描边/填充）
    airui.shape({
        parent = main_container,
        x = 20, y = 100, w = 760, h = 140,
        items = {
            {type = "circle", cx = 80, cy = 70, r = 60,
             color = 0xff3b30, width = 2},
            {type = "circle", cx = 240, cy = 70, r = 60,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "circle", cx = 400, cy = 70, r = 40,
             color = 0xfbbf24, width = 3,
             fill = true, fill_color = 0xfbbf24, fill_opacity = 80},
            {type = "circle", cx = 520, cy = 70, r = 60,
             color = 0x38bdf8, width = 4},
            {type = "circle", cx = 680, cy = 70, r = 50,
             color = 0xa855f7, width = 2,
             fill = true, fill_color = 0x3b0764, fill_opacity = 255},
        },
    })

    -- 示例3：椭圆
    airui.shape({
        parent = main_container,
        x = 20, y = 250, w = 760, h = 80,
        items = {
            {type = "ellipse", cx = 140, cy = 40, rx = 120, ry = 30,
             color = 0xff3b30, width = 2},
            {type = "ellipse", cx = 400, cy = 40, rx = 120, ry = 30,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "ellipse", cx = 660, cy = 40, rx = 100, ry = 30,
             color = 0x38bdf8, width = 3,
             fill = true, fill_color = 0x38bdf8, fill_opacity = 80},
        },
    })

    -- 示例4：矩形和圆角矩形
    airui.shape({
        parent = main_container,
        x = 20, y = 340, w = 760, h = 130,
        items = {
            {type = "rect", x = 40, y = 10, w = 140, h = 100,
             color = 0xff3b30, width = 2},
            {type = "rect", x = 220, y = 10, w = 140, h = 100, radius = 20,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "rect", x = 400, y = 10, w = 140, h = 100, radius = 50,
             color = 0x38bdf8, width = 4,
             fill = true, fill_color = 0x38bdf8, fill_opacity = 60},
            {type = "rect", x = 580, y = 10, w = 140, h = 100, radius = 10,
             color = 0xfbbf24, width = 3,
             fill = true, fill_color = 0x452c08, fill_opacity = 255},
        },
    })

end

sys.taskInit(ui_main)
