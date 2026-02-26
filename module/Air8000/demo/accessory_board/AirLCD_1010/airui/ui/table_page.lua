--[[
@module  table_page
@summary 表格组件演示页面
@version 1.0
@date    2026.02.05
@author  江访
@usage
本文件是表格组件的演示页面，展示表格的各种用法。
]]

local table_page = {}

-- 页面UI元素
local main_container = nil
local update_timer

-- 创建UI
function table_page.create_ui()
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
        color = 0x607D8B,
    })

    airui.label({
        parent = title_bar,
        text = "表格组件演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function(self)
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

    -- 示例1: 基本表格
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本表格",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local basic_table = airui.table({
        parent = scroll_container,
        x = 20,
        y = 40,
        w = 280,
        h = 120,
        rows = 4,
        cols = 3,
        col_width = {80, 100, 80},
        border_color = 0x607D8B,
    })

    basic_table:set_cell_text(0, 0, "姓名")
    basic_table:set_cell_text(0, 1, "年龄")
    basic_table:set_cell_text(0, 2, "城市")

    basic_table:set_cell_text(1, 0, "张三")
    basic_table:set_cell_text(1, 1, "25")
    basic_table:set_cell_text(1, 2, "北京")

    basic_table:set_cell_text(2, 0, "李四")
    basic_table:set_cell_text(2, 1, "30")
    basic_table:set_cell_text(2, 2, "上海")

    basic_table:set_cell_text(3, 0, "王五")
    basic_table:set_cell_text(3, 1, "28")
    basic_table:set_cell_text(3, 2, "广州")

    -- 示例2: 不同边框颜色
    airui.label({
        parent = scroll_container,
        text = "示例2: 不同边框颜色",
        x = 10,
        y = 180,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local color_table = airui.table({
        parent = scroll_container,
        x = 20,
        y = 210,
        w = 280,
        h = 100,
        rows = 3,
        cols = 2,
        col_width = {120, 140},
        border_color = 0xFF5722,
    })

    color_table:set_cell_text(0, 0, "产品")
    color_table:set_cell_text(0, 1, "价格")
    color_table:set_cell_text(1, 0, "手机")
    color_table:set_cell_text(1, 1, "￥2999")
    color_table:set_cell_text(2, 0, "电脑")
    color_table:set_cell_text(2, 1, "￥5999")

    local color_btn1 = airui.button({
        parent = scroll_container,
        x = 20,
        y = 320,
        w = 70,
        h = 30,
        text = "红色",
        on_click = function(self)
            color_table:set_border_color(0xF44336)
        end
    })

    local color_btn2 = airui.button({
        parent = scroll_container,
        x = 100,
        y = 320,
        w = 70,
        h = 30,
        text = "蓝色",
        on_click = function(self)
            color_table:set_border_color(0x2196F3)
        end
    })

    local color_btn3 = airui.button({
        parent = scroll_container,
        x = 180,
        y = 320,
        w = 70,
        h = 30,
        text = "绿色",
        on_click = function(self)
            color_table:set_border_color(0x4CAF50)
        end
    })

    -- 示例3: 动态更新表格
    airui.label({
        parent = scroll_container,
        text = "示例3: 动态更新表格",
        x = 10,
        y = 370,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local dynamic_table = airui.table({
        parent = scroll_container,
        x = 20,
        y = 400,
        w = 280,
        h = 100,
        rows = 3,
        cols = 3,
        col_width = {80, 80, 100},
        border_color = 0x9C27B0,
    })

    dynamic_table:set_cell_text(0, 0, "时间")
    dynamic_table:set_cell_text(0, 1, "温度")
    dynamic_table:set_cell_text(0, 2, "湿度")

    local update_counter = 0
    update_timer = sys.timerLoopStart(function()
        update_counter = update_counter + 1
        local time_str = os.date("%H:%M:%S")
        local temp = math.random(20, 30)
        local humidity = math.random(40, 80)

        dynamic_table:set_cell_text(1, 0, time_str)
        dynamic_table:set_cell_text(1, 1, temp .. "°C")
        dynamic_table:set_cell_text(1, 2, humidity .. "%")

        if update_counter % 2 == 0 then
            dynamic_table:set_cell_text(2, 0, "上次更新")
            dynamic_table:set_cell_text(2, 1, temp .. "°C")
            dynamic_table:set_cell_text(2, 2, humidity .. "%")
        end
    end, 1000)

    local stop_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 510,
        w = 130,
        h = 40,
        text = "停止更新",
        on_click = function(self)
            if update_timer then
                sys.timerStop(update_timer)
                update_timer = nil
                self:set_text("开始更新")
            else
                update_timer = sys.timerLoopStart(function()
                    update_counter = update_counter + 1
                    local time_str = os.date("%H:%M:%S")
                    local temp = math.random(20, 30)
                    local humidity = math.random(40, 80)

                    dynamic_table:set_cell_text(1, 0, time_str)
                    dynamic_table:set_cell_text(1, 1, temp .. "°C")
                    dynamic_table:set_cell_text(1, 2, humidity .. "%")

                    if update_counter % 2 == 0 then
                        dynamic_table:set_cell_text(2, 0, "上次更新")
                        dynamic_table:set_cell_text(2, 1, temp .. "°C")
                        dynamic_table:set_cell_text(2, 2, humidity .. "%")
                    end
                end, 1000)
                self:set_text("停止更新")
            end
        end
    })

    -- 示例4: 调整列宽
    airui.label({
        parent = scroll_container,
        text = "示例4: 调整列宽",
        x = 10,
        y = 560,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local resize_table = airui.table({
        parent = scroll_container,
        x = 20,
        y = 590,
        w = 280,
        h = 80,
        rows = 2,
        cols = 4,
        col_width = {60, 60, 60, 80},
        border_color = 0x009688,
    })

    resize_table:set_cell_text(0, 0, "语文")
    resize_table:set_cell_text(0, 1, "数学")
    resize_table:set_cell_text(0, 2, "英语")
    resize_table:set_cell_text(0, 3, "总分")
    resize_table:set_cell_text(1, 0, "85")
    resize_table:set_cell_text(1, 1, "92")
    resize_table:set_cell_text(1, 2, "78")
    resize_table:set_cell_text(1, 3, "255")

    local resize_btn1 = airui.button({
        parent = scroll_container,
        x = 20,
        y = 680,
        w = 60,
        h = 30,
        text = "窄列",
        on_click = function(self)
            resize_table:set_col_width(0, 40)
            resize_table:set_col_width(1, 40)
            resize_table:set_col_width(2, 40)
            resize_table:set_col_width(3, 60)
        end
    })

    local resize_btn2 = airui.button({
        parent = scroll_container,
        x = 90,
        y = 680,
        w = 60,
        h = 30,
        text = "中列",
        on_click = function(self)
            resize_table:set_col_width(0, 60)
            resize_table:set_col_width(1, 60)
            resize_table:set_col_width(2, 60)
            resize_table:set_col_width(3, 80)
        end
    })

    local resize_btn3 = airui.button({
        parent = scroll_container,
        x = 160,
        y = 680,
        w = 60,
        h = 30,
        text = "宽列",
        on_click = function(self)
            resize_table:set_col_width(0, 80)
            resize_table:set_col_width(1, 80)
            resize_table:set_col_width(2, 80)
            resize_table:set_col_width(3, 100)
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 表格支持动态更新和样式调整",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        font_size = 14,
    })
end

-- 初始化页面
function table_page.init(params)
    math.randomseed(os.time())
    table_page.create_ui()
end

-- 清理页面
function table_page.cleanup()
    if update_timer then
        sys.timerStop(update_timer)
        update_timer = nil
    end
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return table_page