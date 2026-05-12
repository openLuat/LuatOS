--[[
@module shape_page
@summary 形状组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.shape组件的用法，展示直线、圆形、椭圆、矩形/圆角矩形等多种图元绘制。
适用于320x480竖屏。
]]

local function ui_main()
    -- 初始化硬件

    -- 创建主容器
    local main_container = airui.container({
        x = 0, y = 0, w = 320, h = 480,
        color = 0x1a1a2e,
    })

    -- 标题
    airui.label({
        parent = main_container,
        text = "Shape 形状演示",
        x = 0, y = 5, w = 320, h = 24,
        font_size = 18,
        color = 0xffffff,
        align = airui.TEXT_ALIGN_CENTER,
    })

    -- 示例1：直线（含虚线、圆头）
    airui.shape({
        parent = main_container,
        x = 5, y = 35, w = 310, h = 20,
        items = {
            {type = "line", x1 = 0, y1 = 10, x2 = 100, y2 = 10,
             color = 0xff3b30, width = 2},
            {type = "line", x1 = 115, y1 = 10, x2 = 195, y2 = 10,
             color = 0x22c55e, width = 4,
             round_start = true, round_end = true},
            {type = "line", x1 = 210, y1 = 10, x2 = 310, y2 = 10,
             color = 0x38bdf8, width = 2,
             dash_width = 6, dash_gap = 4},
        },
    })

    -- 示例2：圆形
    airui.shape({
        parent = main_container,
        x = 5, y = 62, w = 310, h = 90,
        items = {
            {type = "circle", cx = 35, cy = 45, r = 30,
             color = 0xff3b30, width = 2},
            {type = "circle", cx = 115, cy = 45, r = 30,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "circle", cx = 195, cy = 45, r = 25,
             color = 0xfbbf24, width = 3,
             fill = true, fill_color = 0xfbbf24, fill_opacity = 80},
            {type = "circle", cx = 265, cy = 45, r = 30,
             color = 0xa855f7, width = 2,
             fill = true, fill_color = 0x3b0764, fill_opacity = 255},
        },
    })

    -- 示例3：椭圆
    airui.shape({
        parent = main_container,
        x = 5, y = 160, w = 310, h = 45,
        items = {
            {type = "ellipse", cx = 55, cy = 22, rx = 50, ry = 18,
             color = 0xff3b30, width = 2},
            {type = "ellipse", cx = 160, cy = 22, rx = 50, ry = 18,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "ellipse", cx = 265, cy = 22, rx = 40, ry = 18,
             color = 0x38bdf8, width = 2,
             fill = true, fill_color = 0x38bdf8, fill_opacity = 80},
        },
    })

    -- 示例4：矩形/圆角矩形
    airui.shape({
        parent = main_container,
        x = 5, y = 215, w = 310, h = 75,
        items = {
            {type = "rect", x = 0, y = 5, w = 65, h = 55,
             color = 0xff3b30, width = 2},
            {type = "rect", x = 80, y = 5, w = 65, h = 55, radius = 10,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "rect", x = 160, y = 5, w = 65, h = 55, radius = 25,
             color = 0x38bdf8, width = 3,
             fill = true, fill_color = 0x38bdf8, fill_opacity = 60},
            {type = "rect", x = 240, y = 5, w = 65, h = 55, radius = 8,
             color = 0xfbbf24, width = 2,
             fill = true, fill_color = 0x452c08, fill_opacity = 255},
        },
    })

end

sys.taskInit(ui_main)
