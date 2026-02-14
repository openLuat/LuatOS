--[[
@module  table_page
@summary 表格组件演示页面
@version 1.0.0
@date    2026.01.30
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
        color = 0x607D8B,
    })

    airui.label({
        parent = title_bar,
        text = "表格组件演示",
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

    -- 示例1: 基本表格（左列）
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本表格",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local basic_table = airui.table({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 150,
        rows = 5,
        cols = 4,
        col_width = {100, 100, 100, 100},
        border_color = 0x607D8B,
    })

    -- 设置表头
    basic_table:set_cell_text(0, 0, "姓名")
    basic_table:set_cell_text(0, 1, "年龄")
    basic_table:set_cell_text(0, 2, "城市")
    basic_table:set_cell_text(0, 3, "职业")

    -- 设置数据
    basic_table:set_cell_text(1, 0, "张三")
    basic_table:set_cell_text(1, 1, "25")
    basic_table:set_cell_text(1, 2, "北京")
    basic_table:set_cell_text(1, 3, "工程师")

    basic_table:set_cell_text(2, 0, "李四")
    basic_table:set_cell_text(2, 1, "30")
    basic_table:set_cell_text(2, 2, "上海")
    basic_table:set_cell_text(2, 3, "设计师")

    basic_table:set_cell_text(3, 0, "王五")
    basic_table:set_cell_text(3, 1, "28")
    basic_table:set_cell_text(3, 2, "广州")
    basic_table:set_cell_text(3, 3, "产品经理")

    basic_table:set_cell_text(4, 0, "赵六")
    basic_table:set_cell_text(4, 1, "35")
    basic_table:set_cell_text(4, 2, "深圳")
    basic_table:set_cell_text(4, 3, "架构师")

    -- 示例2: 不同边框颜色（右列）
    airui.label({
        parent = scroll_container,
        text = "示例2: 不同边框颜色",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local color_table = airui.table({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 150,
        rows = 4,
        cols = 3,
        col_width = {140, 140, 140},
        border_color = 0xFF5722,
    })

    color_table:set_cell_text(0, 0, "产品名称")
    color_table:set_cell_text(0, 1, "价格")
    color_table:set_cell_text(0, 2, "库存")
    color_table:set_cell_text(1, 0, "智能手机")
    color_table:set_cell_text(1, 1, "￥2999")
    color_table:set_cell_text(1, 2, "150")
    color_table:set_cell_text(2, 0, "笔记本电脑")
    color_table:set_cell_text(2, 1, "￥5999")
    color_table:set_cell_text(2, 2, "80")
    color_table:set_cell_text(3, 0, "平板电脑")
    color_table:set_cell_text(3, 1, "￥1999")
    color_table:set_cell_text(3, 2, "120")

    -- 颜色选择按钮
    local color_btn1 = airui.button({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 200,
        w = 100,
        h = 40,
        text = "红色",
        size = 14,
        on_click = function()
            color_table:set_border_color(0xF44336)
        end
    })

    local color_btn2 = airui.button({
        parent = scroll_container,
        x = right_column_x + 140,
        y = y_offset + 200,
        w = 100,
        h = 40,
        text = "蓝色",
        size = 14,
        on_click = function()
            color_table:set_border_color(0x2196F3)
        end
    })

    local color_btn3 = airui.button({
        parent = scroll_container,
        x = right_column_x + 260,
        y = y_offset + 200,
        w = 100,
        h = 40,
        text = "绿色",
        size = 14,
        on_click = function()
            color_table:set_border_color(0x4CAF50)
        end
    })

    local color_btn4 = airui.button({
        parent = scroll_container,
        x = right_column_x + 380,
        y = y_offset + 200,
        w = 100,
        h = 40,
        text = "紫色",
        size = 14,
        on_click = function()
            color_table:set_border_color(0x9C27B0)
        end
    })

    y_offset = y_offset + 250

    -- 示例3: 动态更新表格（左列）
    airui.label({
        parent = scroll_container,
        text = "示例3: 动态更新表格",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local dynamic_table = airui.table({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 120,
        rows = 3,
        cols = 3,
        col_width = {120, 120, 160},
        border_color = 0x9C27B0,
    })

    dynamic_table:set_cell_text(0, 0, "时间")
    dynamic_table:set_cell_text(0, 1, "温度")
    dynamic_table:set_cell_text(0, 2, "湿度")

    -- 动态更新数据
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

    -- 控制按钮
    local stop_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 170,
        w = 200,
        h = 45,
        text = "停止更新",
        size = 16,
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

    local reset_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 240,
        y = y_offset + 170,
        w = 200,
        h = 45,
        text = "重置表格",
        size = 16,
        on_click = function()
            dynamic_table:set_cell_text(1, 0, "--:--:--")
            dynamic_table:set_cell_text(1, 1, "0°C")
            dynamic_table:set_cell_text(1, 2, "0%")
            dynamic_table:set_cell_text(2, 0, "等待更新")
            dynamic_table:set_cell_text(2, 1, "0°C")
            dynamic_table:set_cell_text(2, 2, "0%")
        end
    })

    -- 示例4: 调整列宽（右列）
    airui.label({
        parent = scroll_container,
        text = "示例4: 调整列宽",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local resize_table = airui.table({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 120,
        rows = 3,
        cols = 4,
        col_width = {100, 100, 100, 100},
        border_color = 0x009688,
    })

    resize_table:set_cell_text(0, 0, "科目")
    resize_table:set_cell_text(0, 1, "语文")
    resize_table:set_cell_text(0, 2, "数学")
    resize_table:set_cell_text(0, 3, "英语")
    resize_table:set_cell_text(1, 0, "成绩")
    resize_table:set_cell_text(1, 1, "85")
    resize_table:set_cell_text(1, 2, "92")
    resize_table:set_cell_text(1, 3, "78")
    resize_table:set_cell_text(2, 0, "总分")
    resize_table:set_cell_text(2, 1, "255")
    resize_table:set_cell_text(2, 2, "255")
    resize_table:set_cell_text(2, 3, "255")

    -- 列宽调整按钮
    local resize_btn1 = airui.button({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 170,
        w = 100,
        h = 40,
        text = "窄列",
        size = 14,
        on_click = function()
            resize_table:set_col_width(0, 70)
            resize_table:set_col_width(1, 70)
            resize_table:set_col_width(2, 70)
            resize_table:set_col_width(3, 70)
        end
    })

    local resize_btn2 = airui.button({
        parent = scroll_container,
        x = right_column_x + 140,
        y = y_offset + 170,
        w = 100,
        h = 40,
        text = "中列",
        size = 14,
        on_click = function()
            resize_table:set_col_width(0, 100)
            resize_table:set_col_width(1, 100)
            resize_table:set_col_width(2, 100)
            resize_table:set_col_width(3, 100)
        end
    })

    local resize_btn3 = airui.button({
        parent = scroll_container,
        x = right_column_x + 260,
        y = y_offset + 170,
        w = 100,
        h = 40,
        text = "宽列",
        size = 14,
        on_click = function()
            resize_table:set_col_width(0, 130)
            resize_table:set_col_width(1, 130)
            resize_table:set_col_width(2, 130)
            resize_table:set_col_width(3, 130)
        end
    })

    local reset_width_btn = airui.button({
        parent = scroll_container,
        x = right_column_x + 380,
        y = y_offset + 170,
        w = 100,
        h = 40,
        text = "重置",
        size = 14,
        on_click = function()
            resize_table:set_col_width(0, 100)
            resize_table:set_col_width(1, 100)
            resize_table:set_col_width(2, 100)
            resize_table:set_col_width(3, 100)
        end
    })

    y_offset = y_offset + 230

    -- 示例5: 快速创建表格（左列）
    airui.label({
        parent = scroll_container,
        text = "示例5: 快速创建表格",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local multi_row_table = airui.table({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 200,
        rows = 8,
        cols = 3,
        col_width = {140, 140, 140},
        border_color = 0x673AB7,
    })

    multi_row_table:set_cell_text(0, 0, "编号")
    multi_row_table:set_cell_text(0, 1, "产品名称")
    multi_row_table:set_cell_text(0, 2, "库存量")
    
    for i = 1, 7 do
        multi_row_table:set_cell_text(i, 0, "P" .. i)
        multi_row_table:set_cell_text(i, 1, "产品" .. i)
        multi_row_table:set_cell_text(i, 2, tostring(math.random(10, 200)))
    end

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 表格支持动态更新、样式调整和多行列配置",
        x = 20,
        y = 560,
        w = 500,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function table_page.init(params)
    math.randomseed(os.time())
    table_page.create_ui()
end

-- 清理页面
function table_page.cleanup()
    sys.timerStop(update_timer)
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return table_page