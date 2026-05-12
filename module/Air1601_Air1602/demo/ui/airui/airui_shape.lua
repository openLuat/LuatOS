--[[
@module shape_page
@summary 形状组件演示
@version 1.0
@date 2026.05.12
@author 江访
@usage
本文件演示airui.shape组件的用法，展示直线、圆形、椭圆、矩形/圆角矩形等多种图元绘制。
]]

local airui_shape = {}

local main_container = nil

function airui_shape.create_ui()
    main_container = airui.container({
        x = 0, y = 0, w = 1024, h = 600,
        color = 0x1a1a2e,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0, y = 0, w = 1024, h = 60,
        color = 0x4CAF50,
    })

    airui.label({
        parent = title_bar,
        text = "形状组件演示",
        x = 20, y = 15, w = 300, h = 30,
        size = 20,
        color = 0xffffff,
    })

    -- 返回按钮
    airui.button({
        parent = title_bar,
        x = 900, y = 15, w = 100, h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- 示例1：直线
    airui.shape({
        parent = main_container,
        x = 40, y = 75, w = 944, h = 30,
        items = {
            {type = "line", x1 = 0, y1 = 15, x2 = 280, y2 = 15,
             color = 0xff3b30, width = 2},
            {type = "line", x1 = 320, y1 = 15, x2 = 600, y2 = 15,
             color = 0x22c55e, width = 6,
             round_start = true, round_end = true},
            {type = "line", x1 = 640, y1 = 15, x2 = 944, y2 = 15,
             color = 0x38bdf8, width = 2,
             dash_width = 8, dash_gap = 6},
        },
    })

    -- 示例2：圆形
    airui.shape({
        parent = main_container,
        x = 40, y = 115, w = 944, h = 120,
        items = {
            {type = "circle", cx = 80, cy = 60, r = 50,
             color = 0xff3b30, width = 2},
            {type = "circle", cx = 240, cy = 60, r = 50,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "circle", cx = 420, cy = 60, r = 40,
             color = 0xfbbf24, width = 3,
             fill = true, fill_color = 0xfbbf24, fill_opacity = 80},
            {type = "circle", cx = 580, cy = 60, r = 50,
             color = 0x38bdf8, width = 4},
            {type = "circle", cx = 760, cy = 60, r = 50,
             color = 0xa855f7, width = 2,
             fill = true, fill_color = 0x3b0764, fill_opacity = 255},
        },
    })

    -- 示例3：椭圆
    airui.shape({
        parent = main_container,
        x = 40, y = 255, w = 944, h = 60,
        items = {
            {type = "ellipse", cx = 140, cy = 30, rx = 120, ry = 25,
             color = 0xff3b30, width = 2},
            {type = "ellipse", cx = 410, cy = 30, rx = 120, ry = 25,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "ellipse", cx = 680, cy = 30, rx = 120, ry = 25,
             color = 0x38bdf8, width = 3,
             fill = true, fill_color = 0x38bdf8, fill_opacity = 80},
        },
    })

    -- 示例4：矩形/圆角矩形
    airui.shape({
        parent = main_container,
        x = 40, y = 335, w = 944, h = 120,
        items = {
            {type = "rect", x = 36, y = 15, w = 180, h = 90,
             color = 0xff3b30, width = 2},
            {type = "rect", x = 268, y = 15, w = 180, h = 90, radius = 20,
             color = 0x22c55e, width = 2,
             fill = true, fill_color = 0x14532d, fill_opacity = 200},
            {type = "rect", x = 500, y = 15, w = 180, h = 90, radius = 45,
             color = 0x38bdf8, width = 4,
             fill = true, fill_color = 0x38bdf8, fill_opacity = 60},
            {type = "rect", x = 732, y = 15, w = 180, h = 90, radius = 10,
             color = 0xfbbf24, width = 3,
             fill = true, fill_color = 0x452c08, fill_opacity = 255},
        },
    })

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0, y = 550, w = 1024, h = 50,
        color = 0xCFCFCF,
    })

    airui.label({
        parent = status_bar,
        text = "直线/圆形/椭圆/矩形/圆角矩形 四种图元演示",
        x = 20, y = 15, w = 600, h = 20,
        size = 14,
        color = 0x333333,
    })
end

function airui_shape.init(params)
    airui_shape.create_ui()
end

function airui_shape.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return airui_shape
