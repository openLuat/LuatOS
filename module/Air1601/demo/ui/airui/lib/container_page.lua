--[[
@module  container_page
@summary 容器组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是容器组件的演示页面，展示容器的各种用法。
]]

local container_page = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function container_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 1024,
        h = 600,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = 0xFF9800,
    })

    airui.label({
        parent = title_bar,
        text = "容器组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        size = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 70,
        w = 1024,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 使用两列布局
    local left_column_x = 20
    local right_column_x = 522
    local y_offset = 10
    local section_height = 130

    -- 示例1: 基本容器（左列）
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本容器",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local basic_container = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 100,
        color = 0xE3F2FD,
        radius = 12,
    })

    airui.label({
        parent = basic_container,
        text = "这是一个基本容器",
        x = 20,
        y = 15,
        w = 400,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = basic_container,
        text = "容器可以作为其他组件的父容器",
        x = 20,
        y = 55,
        w = 400,
        h = 30,
        size = 14,
    })

    -- 示例2: 圆角容器（右列）
    airui.label({
        parent = scroll_container,
        text = "示例2: 圆角容器",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local rounded_container = airui.container({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 100,
        color = 0xFFEBEE,
        radius = 30,
    })

    airui.label({
        parent = rounded_container,
        text = "圆角半径: 30",
        x = 20,
        y = 35,
        w = 400,
        h = 30,
        size = 16,
    })

    y_offset = y_offset + section_height + 20

    -- 示例3: 嵌套容器（左列）
    airui.label({
        parent = scroll_container,
        text = "示例3: 嵌套容器",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local parent_container = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 150,
        color = 0xE8F5E8,
        radius = 12,
    })

    local child1 = airui.container({
        parent = parent_container,
        x = 20,
        y = 20,
        w = 180,
        h = 60,
        color = 0xC8E6C9,
        radius = 8,
    })

    airui.label({
        parent = child1,
        text = "子容器1",
        x = 20,
        y = 20,
        w = 140,
        h = 20,
        size = 14,
    })

    local child2 = airui.container({
        parent = parent_container,
        x = 240,
        y = 20,
        w = 180,
        h = 60,
        color = 0xA5D6A7,
        radius = 8,
    })

    airui.label({
        parent = child2,
        text = "子容器2",
        x = 20,
        y = 20,
        w = 140,
        h = 20,
        size = 14,
    })

    local child3 = airui.container({
        parent = parent_container,
        x = 20,
        y = 90,
        w = 400,
        h = 40,
        color = 0x81C784,
        radius = 6,
    })

    airui.label({
        parent = child3,
        text = "另一个子容器",
        x = 20,
        y = 10,
        w = 360,
        h = 20,
        size = 14,
    })

    -- 示例4: 不同颜色的容器（右列）
    airui.label({
        parent = scroll_container,
        text = "示例4: 不同颜色的容器",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local color_container1 = airui.container({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 130,
        h = 70,
        color = 0xF44336,
        radius = 10,
    })

    airui.label({
        parent = color_container1,
        text = "红色",
        x = 20,
        y = 25,
        w = 90,
        h = 20,
        size = 14,
    })

    local color_container2 = airui.container({
        parent = scroll_container,
        x = right_column_x + 165,
        y = y_offset + 40,
        w = 130,
        h = 70,
        color = 0x4CAF50,
        radius = 10,
    })

    airui.label({
        parent = color_container2,
        text = "绿色",
        x = 20,
        y = 25,
        w = 90,
        h = 20,
        size = 14,
    })

    local color_container3 = airui.container({
        parent = scroll_container,
        x = right_column_x + 310,
        y = y_offset + 40,
        w = 130,
        h = 70,
        color = 0x2196F3,
        radius = 10,
    })

    airui.label({
        parent = color_container3,
        text = "蓝色",
        x = 20,
        y = 25,
        w = 90,
        h = 20,
        size = 14,
    })

    y_offset = y_offset + 200

    -- 示例5: 动态显示/隐藏容器（左列）
    airui.label({
        parent = scroll_container,
        text = "示例5: 显示/隐藏容器",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local toggle_container = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 250,
        h = 80,
        color = 0xE1BEE7,
        radius = 12,
    })

    airui.label({
        parent = toggle_container,
        text = "可隐藏的容器",
        x = 20,
        y = 30,
        w = 210,
        h = 20,
        size = 16,
    })

    local hide_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 290,
        y = y_offset + 40,
        w = 120,
        h = 35,
        text = "隐藏",
        size = 16,
        on_click = function(self)
            if toggle_container then
                toggle_container:hide()
            end
        end
    })

    local show_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 290,
        y = y_offset + 80,
        w = 120,
        h = 35,
        text = "显示",
        size = 16,
        on_click = function(self)
            if toggle_container then
                toggle_container:show()
            end
        end
    })

    -- 示例6: 动态改变颜色（右列）
    airui.label({
        parent = scroll_container,
        text = "示例6: 动态改变颜色",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local color_container = airui.container({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 300,
        h = 80,
        color = 0x2196F3,
        radius = 12,
    })

    airui.label({
        parent = color_container,
        text = "点击按钮改变颜色",
        x = 20,
        y = 30,
        w = 260,
        h = 20,
        size = 16,
    })

    local color_btn = airui.button({
        parent = scroll_container,
        x = right_column_x + 340,
        y = y_offset + 40,
        w = 120,
        h = 35,
        text = "随机颜色",
        size = 16,
        on_click = function()
            local colors = {0xFF5722, 0x4CAF50, 0x9C27B0, 0xFF9800, 0x00BCD4, 0x795548, 0x607D8B}
            local random_color = colors[math.random(1, #colors)]
            color_container:set_color(random_color)
        end
    })

    local reset_btn = airui.button({
        parent = scroll_container,
        x = right_column_x + 340,
        y = y_offset + 80,
        w = 120,
        h = 35,
        text = "重置颜色",
        size = 16,
        on_click = function()
            color_container:set_color(0x2196F3)
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 容器是布局的基础组件，支持嵌套和动态样式",
        x = 20,
        y = 560,
        w = 500,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function container_page.init(params)
    math.randomseed(os.time())
    container_page.create_ui()
end

-- 清理页面
function container_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return container_page