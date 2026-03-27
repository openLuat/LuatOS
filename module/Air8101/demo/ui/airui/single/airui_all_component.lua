--[[
@module all_component_page
@summary 所有组件综合演示
@version 2.0
@date 2026.03.09
@author 江访
@usage
本文件演示所有AirUI组件的综合用法。
]]

local function ui_main()
    -- 初始化硬件


    -- 创建主容器
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 800,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 1. 标题区域
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 800,
        h = 60,
        color = 0x007AFF,
    })

    local title_label = airui.label({
        parent = title_bar,
        text = "AirUI 全部组件演示",
        x = 20,
        y = 20,
        w = 760,
        h = 30,
    })

    -- 2. 左列组件
    local left_col = airui.container({
        parent = main_container,
        x = 20,
        y = 70,
        w = 380,
        h = 380,
        color = 0xFFFFFF,
        radius = 8,
    })

    -- 2.1 文本输入框组件
    airui.label({
        parent = left_col,
        text = "文本输入",
        x = 20,
        y = 20,
        w = 100,
        h = 25,
    })

    -- 创建虚拟键盘
    local keyboard = airui.keyboard({
        x = 0,
        y = -20, -- 底部留20像素边距
        w = 800,
        h = 250,
        mode = "text",
        auto_hide = true,
    })

    -- 创建输入框并绑定键盘
    local text_input = airui.textarea({
        parent = left_col,
        x = 20,
        y = 50,
        w = 340,
        h = 60,
        max_len = 50,
        text = "示例文本",
        placeholder = "请输入...",
        keyboard = keyboard,
        on_text_change = function(text)
            log.info("textarea", text)
        end
    })

    -- 2.2 进度条组件
    airui.label({
        parent = left_col,
        text = "进度条",
        x = 20,
        y = 130,
        w = 100,
        h = 25,
    })

    local progress_bar = airui.bar({
        parent = left_col,
        x = 20,
        y = 160,
        w = 340,
        h = 20,
        value = 65,
        bg_color = 0xE0E0E0,
        indicator_color = 0x4CAF50,
        radius = 10,
    })

    -- 2.3 按钮组件
    local test_btn = airui.button({
        parent = left_col,
        x = 20,
        y = 200,
        w = 150,
        h = 40,
        text = "更新进度条",
        on_click = function()
            local current = progress_bar:get_value()
            local new_value = current + 10
            if new_value > 100 then
                new_value = 0
            end
            progress_bar:set_value(new_value, true)
            log.info("progress", "进度更新为: " .. new_value .. "%")
        end
    })

    -- 2.4 消息框按钮
    local msgbox_btn = airui.button({
        parent = left_col,
        x = 200,
        y = 200,
        w = 150,
        h = 40,
        text = "显示消息框",
        on_click = function()
            local msgbox = airui.msgbox({
                title = "提示",
                text = "这是消息框演示\n点击确定关闭",
                buttons = { "确定", "取消" },
                timeout = 2000,
                on_action = function(self, label)
                    log.info("msgbox", "点击了: " .. label)
                    self:hide()
                end
            })
        end
    })

    -- 2.5 下拉框组件
    airui.label({
        parent = left_col,
        text = "下拉选择",
        x = 20,
        y = 250,
        w = 100,
        h = 25,
    })

    local dropdown = airui.dropdown({
        parent = left_col,
        x = 20,
        y = 280,
        w = 200,
        h = 40,
        options = { "选项一", "选项二", "选项三", "选项四" },
        default_index = 0,
        on_change = function(self, index)
            local texts = { "选项一", "选项二", "选项三", "选项四" }
            log.info("dropdown", "选择了: " .. texts[index + 1])
        end
    })

    -- 2.6 开关组件
    airui.label({
        parent = left_col,
        text = "开关",
        x = 240,
        y = 250,
        w = 60,
        h = 30,
    })

    -- 使用一个变量来跟踪当前状态
    local is_on = true -- 初始为ON，与switch的checked=true对应

    local toggle_switch = airui.switch({
        parent = left_col,
        x = 240,
        y = 280,
        checked = true,
        on_change = function(self)
            -- 切换状态
            is_on = not is_on
            -- 根据状态更新日志
            if is_on then
                log.info("当前状态: 开")
            else
                log.info("当前状态: 关")
            end
        end
    })

    -- 2.7 在左列底部添加图表组件（折线图）
    airui.label({
        parent = left_col,
        text = "图表（简化）",
        x = 20,
        y = 320,
        w = 100,
        h = 20,
    })

    local chart = airui.chart({
        parent = left_col,
        x = 20,
        y = 340,
        w = 340,
        h = 40,
        type = "line",
        y_min = 0,
        y_max = 100,
        point_count = 30,
        line_color = 0x00b4ff,
        line_width = 1,
        point_radius = 1,
        legend = false,
        x_axis = { enable = false },
        y_axis = { enable = false },
    })
    -- 设置一些示例数据
    chart:set_values(1, {30, 45, 60, 55, 70, 65, 80, 75, 90, 85, 95})

    -- 3. 右列组件
    local right_col = airui.container({
        parent = main_container,
        x = 420,
        y = 70,
        w = 360,
        h = 380,
        color = 0xFFFFFF,
        radius = 8,
    })

    -- 右列标题
    airui.label({
        parent = right_col,
        text = "数据表格",
        x = 20,
        y = 20,
        w = 320,
        h = 25,
    })

    -- 3.1 表格组件
    local data_table = airui.table({
        parent = right_col,
        x = 20,
        y = 60,
        w = 320,
        h = 220,
        rows = 3,
        cols = 3,
        col_width = { 100, 100, 100 },
        border_color = 0xCCCCCC
    })

    -- 设置表格内容
    data_table:set_cell_text(0, 0, "姓名")
    data_table:set_cell_text(0, 1, "年龄")
    data_table:set_cell_text(0, 2, "城市")
    data_table:set_cell_text(1, 0, "张三")
    data_table:set_cell_text(1, 1, "25")
    data_table:set_cell_text(1, 2, "北京")
    data_table:set_cell_text(2, 0, "李四")
    data_table:set_cell_text(2, 1, "30")
    data_table:set_cell_text(2, 2, "上海")

    -- 3.2 二维码组件
    airui.label({
        parent = right_col,
        text = "二维码",
        x = 20,
        y = 290,
        w = 100,
        h = 20,
    })

    local qrcode = airui.qrcode({
        parent = right_col,
        x = 125,          -- 居中 (360-70)/2 = 145, 但考虑标签文字占用左边距，微调
        y = 310,
        size = 70,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true
    })

    -- 4. 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 460,
        w = 800,
        h = 20,
        color = 0xCFCFCF,
    })

    airui.label({
        parent = status_bar,
        text = "AirUI Demo v1.1",
        x = 20,
        y = 2,
        w = 760,
        h = 16,
    })

end

sys.taskInit(ui_main)