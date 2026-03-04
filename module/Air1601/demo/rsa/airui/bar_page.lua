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
        color = 0x9C27B0,
    })

    airui.label({
        parent = title_bar,
        text = "进度条组件演示",
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
    local section_height = 100

    -- 示例1: 基本进度条（左列）
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本进度条",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local basic_bar = airui.bar({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 400,
        h = 30,
        value = 30,
        min = 0,
        max = 100,
        radius = 15,
        indicator_color = 0x4CAF50,
    })

    airui.label({
        parent = scroll_container,
        text = "30%",
        x = left_column_x + 430,
        y = y_offset + 40,
        w = 50,
        h = 30,
        size = 16,
    })

    -- 示例2: 带边框的进度条（右列）
    airui.label({
        parent = scroll_container,
        text = "示例2: 带边框进度条",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local bordered_bar = airui.bar({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 400,
        h = 35,
        value = 50,
        min = 0,
        max = 100,
        radius = 17,
        border_width = 3,
        border_color = 0x9C27B0,
        indicator_color = 0x9C27B0,
        bg_color = 0xF3E5F5,
    })

    airui.label({
        parent = scroll_container,
        text = "50%",
        x = right_column_x + 430,
        y = y_offset + 40,
        w = 50,
        h = 30,
        size = 16,
    })

    y_offset = y_offset + section_height

    -- 示例3: 动画进度条（左列）
    airui.label({
        parent = scroll_container,
        text = "示例3: 动画进度条",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    -- 显示当前值
    value_label = airui.label({
        parent = scroll_container,
        text = "当前值: 0%",
        x = left_column_x + 360,
        y = y_offset + 45,
        w = 120,
        h = 30,
        size = 16,
    })

    animated_bar = airui.bar({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 320,
        h = 35,
        value = 0,
        min = 0,
        max = 100,
        radius = 17,
        indicator_color = 0x2196F3,
    })

    -- 控制按钮
    local start_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 85,
        w = 120,
        h = 50,
        text = "开始/暂停",
        size = 16,
        on_click = function(self)
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
        x = left_column_x + 160,
        y = y_offset + 85,
        w = 120,
        h = 50,
        text = "重置",
        size = 16,
        on_click = function()
            if update_timer then
                sys.timerStop(update_timer)
                update_timer = nil
                start_btn:set_text("开始动画")
            end
            animated_bar:set_value(0, true)
            value_label:set_text("当前值: 0%")
        end
    })

    local set_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 300,
        y = y_offset + 85,
        w = 120,
        h = 50,
        text = "设为75%",
        size = 16,
        on_click = function()
            if update_timer then
                sys.timerStop(update_timer)
                update_timer = nil
                start_btn:set_text("开始动画")
            end
            animated_bar:set_value(75, true)
            value_label:set_text("当前值: 75%")
        end
    })

    -- 示例4: 不同颜色进度条（右列）
    airui.label({
        parent = scroll_container,
        text = "示例4: 不同颜色进度条",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local color_bar = airui.bar({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 400,
        h = 35,
        value = 75,
        min = 0,
        max = 100,
        radius = 17,
        indicator_color = 0xFF5722,
    })

    airui.label({
        parent = scroll_container,
        text = "75%",
        x = right_column_x + 430,
        y = y_offset + 40,
        w = 50,
        h = 30,
        size = 16,
    })

    -- 颜色选择按钮
    local color_btn1 = airui.button({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 85,
        w = 100,
        h = 40,
        text = "红色",
        size = 14,
        on_click = function()
            color_bar:set_indicator_color(0xF44336)
        end
    })

    local color_btn2 = airui.button({
        parent = scroll_container,
        x = right_column_x + 130,
        y = y_offset + 85,
        w = 100,
        h = 40,
        text = "绿色",
        size = 14,
        on_click = function()
            color_bar:set_indicator_color(0x4CAF50)
        end
    })

    local color_btn3 = airui.button({
        parent = scroll_container,
        x = right_column_x + 240,
        y = y_offset + 85,
        w = 100,
        h = 40,
        text = "蓝色",
        size = 14,
        on_click = function()
            color_bar:set_indicator_color(0x2196F3)
        end
    })

    local color_btn4 = airui.button({
        parent = scroll_container,
        x = right_column_x + 350,
        y = y_offset + 85,
        w = 100,
        h = 40,
        text = "紫色",
        size = 14,
        on_click = function()
            color_bar:set_indicator_color(0x9C27B0)
        end
    })

    y_offset = y_offset + section_height + 70

    -- 示例5: 不同进度的进度条（左列）
    airui.label({
        parent = scroll_container,
        text = "示例5: 不同进度示例",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local bar1 = airui.bar({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 320,
        h = 25,
        value = 25,
        indicator_color = 0xF44336,
    })

    airui.label({
        parent = scroll_container,
        text = "25% - 低进度",
        x = left_column_x + 350,
        y = y_offset + 40,
        w = 120,
        h = 25,
        size = 14,
    })

    local bar2 = airui.bar({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 75,
        w = 320,
        h = 25,
        value = 50,
        indicator_color = 0xFF9800,
    })

    airui.label({
        parent = scroll_container,
        text = "50% - 中等进度",
        x = left_column_x + 350,
        y = y_offset + 75,
        w = 120,
        h = 25,
        size = 14,
    })

    local bar3 = airui.bar({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 110,
        w = 320,
        h = 25,
        value = 90,
        indicator_color = 0x4CAF50,
    })

    airui.label({
        parent = scroll_container,
        text = "90% - 高进度",
        x = left_column_x + 350,
        y = y_offset + 110,
        w = 120,
        h = 25,
        size = 14,
    })

    -- 示例6: 自定义背景色（右列）
    airui.label({
        parent = scroll_container,
        text = "示例6: 自定义背景色",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local custom_bar = airui.bar({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 400,
        h = 35,
        value = 65,
        radius = 17,
        indicator_color = 0xFF4081,
        bg_color = 0xFCE4EC,
        border_width = 2,
        border_color = 0xFF4081,
    })

    airui.label({
        parent = scroll_container,
        text = "65% - 粉色主题",
        x = right_column_x + 20,
        y = y_offset + 85,
        w = 120,
        h = 35,
        size = 14,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 进度条支持动画、颜色自定义和边框样式",
        x = 20,
        y = 560,
        w = 500,
        h = 25,
        size = 14,
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