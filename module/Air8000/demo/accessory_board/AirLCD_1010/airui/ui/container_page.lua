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
        w = 320,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0xFF9800,
    })

    airui.label({
        parent = title_bar,
        text = "容器组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function()
            go_back()
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 370,
        color = 0xF5F5F5,
    })

    -- 示例1: 基本容器
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本容器",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
    })

    local basic_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 40,
        w = 280,
        h = 80,
        color = 0xE3F2FD,
        radius = 8,
    })

    airui.label({
        parent = basic_container,
        text = "这是一个容器",
        x = 10,
        y = 10,
        w = 260,
        h = 20,
    })

    airui.label({
        parent = basic_container,
        text = "容器可以作为其他组件的父容器",
        x = 10,
        y = 40,
        w = 260,
        h = 20,
    })

    -- 示例2: 圆角容器
    airui.label({
        parent = scroll_container,
        text = "示例2: 圆角容器",
        x = 10,
        y = 130,
        w = 300,
        h = 20,
    })

    local rounded_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 160,
        w = 280,
        h = 80,
        color = 0xFFEBEE,
        radius = 20,
    })

    airui.label({
        parent = rounded_container,
        text = "圆角半径: 20",
        x = 10,
        y = 30,
        w = 260,
        h = 20,
    })

    -- 示例3: 嵌套容器
    airui.label({
        parent = scroll_container,
        text = "示例3: 嵌套容器",
        x = 10,
        y = 250,
        w = 300,
        h = 20,
    })

    local parent_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 280,
        w = 280,
        h = 120,
        color = 0xE8F5E8,
        radius = 10,
    })

    local child1 = airui.container({
        parent = parent_container,
        x = 10,
        y = 10,
        w = 120,
        h = 50,
        color = 0xC8E6C9,
        radius = 5,
    })

    airui.label({
        parent = child1,
        text = "子容器1",
        x = 10,
        y = 15,
        w = 100,
        h = 20,
    })

    local child2 = airui.container({
        parent = parent_container,
        x = 150,
        y = 10,
        w = 120,
        h = 50,
        color = 0xA5D6A7,
        radius = 5,
    })

    airui.label({
        parent = child2,
        text = "子容器2",
        x = 10,
        y = 15,
        w = 100,
        h = 20,
    })

    -- 示例4: 动态显示/隐藏
    airui.label({
        parent = scroll_container,
        text = "示例4: 显示/隐藏容器",
        x = 10,
        y = 410,
        w = 300,
        h = 20,
    })

    local toggle_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 440,
        w = 160,
        h = 60,
        color = 0xE1BEE7,
        radius = 8,
    })

    airui.label({
        parent = toggle_container,
        text = "可隐藏的容器",
        x = 10,
        y = 20,
        w = 140,
        h = 20,
    })

    local toggle_btn = airui.button({
        parent = scroll_container,
        x = 190,
        y = 450,
        w = 100,
        h = 40,
        text = "隐藏",
        on_click = function(self)
            if toggle_container then
                toggle_container:hide()
            end
        end
    })

    -- 示例5: 动态改变颜色
    airui.label({
        parent = scroll_container,
        text = "示例5: 动态改变颜色",
        x = 10,
        y = 510,
        w = 300,
        h = 20,
    })

    local color_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 540,
        w = 280,
        h = 80,
        color = 0x2196F3,
        radius = 8,
    })

    airui.label({
        parent = color_container,
        text = "点击按钮改变颜色",
        x = 10,
        y = 30,
        w = 260,
        h = 20,
    })

    local color_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 630,
        w = 130,
        h = 40,
        text = "随机颜色",
        on_click = function()
            local colors = {0xFF5722, 0x4CAF50, 0x9C27B0, 0xFF9800, 0x00BCD4}
            local random_color = colors[math.random(1, #colors)]
            color_container:set_color(random_color)
        end
    })

    local reset_btn = airui.button({
        parent = scroll_container,
        x = 170,
        y = 630,
        w = 130,
        h = 40,
        text = "重置颜色",
        on_click = function()
            color_container:set_color(0x2196F3)
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 容器是布局的基础组件",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
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