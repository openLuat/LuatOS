--[[
@module  bar_page
@summary 进度条组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是进度条组件的演示页面，展示进度条的各种用法。
]]

local bar_page = {}

-- 页面UI元素
local main_container = nil
local progress_value = 0
local value_label
local update_timer
local animated_bar

-- 创建UI
function bar_page.create_ui()
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
        color = 0x9C27B0,
    })

    airui.label({
        parent = title_bar,
        text = "进度条组件演示",
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

    -- 示例1: 基本进度条
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本进度条",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
    })

    local basic_bar = airui.bar({
        parent = scroll_container,
        x = 20,
        y = 40,
        w = 280,
        h = 20,
        value = 30,
        min = 0,
        max = 100,
        radius = 10,
        indicator_color = 0x4CAF50,
    })

    -- 示例2: 带边框的进度条
    airui.label({
        parent = scroll_container,
        text = "示例2: 带边框进度条",
        x = 10,
        y = 80,
        w = 300,
        h = 20,
    })

    local bordered_bar = airui.bar({
        parent = scroll_container,
        x = 20,
        y = 110,
        w = 280,
        h = 25,
        value = 50,
        min = 0,
        max = 100,
        radius = 12,
        border_width = 2,
        border_color = 0x9C27B0,
        indicator_color = 0x9C27B0,
        bg_color = 0xF3E5F5,
    })

    -- 示例3: 动画进度条
    airui.label({
        parent = scroll_container,
        text = "示例3: 动画进度条",
        x = 10,
        y = 150,
        w = 300,
        h = 20,
    })

    -- 显示当前值
    value_label = airui.label({
        parent = scroll_container,
        text = "当前值: 0%",
        x = 210,
        y = 225,
        w = 90,
        h = 30,
    })

    animated_bar = airui.bar({
        parent = scroll_container,
        x = 20,
        y = 180,
        w = 280,
        h = 25,
        value = 0,
        min = 0,
        max = 100,
        radius = 12,
        indicator_color = 0x2196F3,
    })

    -- 控制按钮
    local start_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 220,
        w = 80,
        h = 40,
        text = "开始",
        on_click = function()
            if update_timer then
                sys.timerStop(update_timer)
                update_timer = nil
            else
                update_timer = sys.timerLoopStart(function()
                    local current = animated_bar:get_value()
                    if current >= 100 then
                        current = 0
                    else
                        current = current + 5
                    end
                    animated_bar:set_value(current, true) -- 启用动画
                    value_label:set_text("当前值: "..current.."%") -- 更新显示
                    progress_value = current

                    if current >= 100 then
                        sys.timerStop(update_timer)
                        update_timer = nil
                    end
                end, 200)
            end
        end
    })

    local reset_btn = airui.button({
        parent = scroll_container,
        x = 120,
        y = 220,
        w = 80,
        h = 40,
        text = "重置",
        on_click = function()
            if update_timer then
                sys.timerStop(update_timer)
                update_timer = nil
                start_btn:set_text("开始")
            end
            animated_bar:set_value(0, true)
        end
    })



    -- 示例4: 不同颜色进度条
    airui.label({
        parent = scroll_container,
        text = "示例4: 不同颜色进度条",
        x = 10,
        y = 280,
        w = 300,
        h = 20,
    })

    local color_bar = airui.bar({
        parent = scroll_container,
        x = 20,
        y = 310,
        w = 280,
        h = 20,
        value = 75,
        min = 0,
        max = 100,
        radius = 10,
        indicator_color = 0xFF5722,
    })

    -- 颜色选择
    local color_btn1 = airui.button({
        parent = scroll_container,
        x = 20,
        y = 340,
        w = 60,
        h = 30,
        text = "红色",
        on_click = function()
            color_bar:set_indicator_color(0xF44336)
        end
    })

    local color_btn2 = airui.button({
        parent = scroll_container,
        x = 90,
        y = 340,
        w = 60,
        h = 30,
        text = "绿色",
        on_click = function()
            color_bar:set_indicator_color(0x4CAF50)
        end
    })

    local color_btn3 = airui.button({
        parent = scroll_container,
        x = 160,
        y = 340,
        w = 60,
        h = 30,
        text = "蓝色",
        on_click = function()
            color_bar:set_indicator_color(0x2196F3)
        end
    })

    local color_btn4 = airui.button({
        parent = scroll_container,
        x = 230,
        y = 340,
        w = 60,
        h = 30,
        text = "紫色",
        on_click = function()
            color_bar:set_indicator_color(0x9C27B0)
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 进度条支持动画和颜色自定义",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
    })
end

-- 初始化页面
function bar_page.init(params)
    progress_value = 0
    bar_page.create_ui()
end

-- 清理页面
function bar_page.cleanup()
    sys.timerStop(update_timer)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return bar_page