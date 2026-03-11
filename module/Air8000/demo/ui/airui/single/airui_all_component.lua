--[[
@module all_component_page
@summary 所有组件综合演示
@version 1.1
@date 2026.03.09
@author 江访
@usage
本文件演示所有AirUI组件的综合用法，展示完整UI界面。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建主容器（竖屏尺寸）
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 1. 标题区域
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0x007AFF,
    })

    airui.label({
        parent = title_bar,
        text = "AirUI组件演示",
        x = 10,
        y = 10,
        w = 300,
        h = 30,
    })

    -- 2. 内容区域（可滚动容器）
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,
        w = 320,
        h = 380,    -- 固定高度，内部可滚动
        color = 0xFFFFFF,
    })

    -- 当前Y坐标游标（起始留出上边距）
    local y = 10

    -- 2.1 文本输入框组件
    airui.label({
        parent = scroll_container,
        text = "文本输入",
        x = 10,
        y = y,
        w = 300,
        h = 14,
        font_size = 12,
        color = 0x333333,
    })
    y = y + 14 + 5

    local text_input = airui.textarea({
        parent = scroll_container,
        x = 10,
        y = y,
        w = 300,
        h = 40,          -- 高度40，显示更舒适
        max_len = 50,
        text = "示例文本",
        placeholder = "请输入...",
        on_text_change = function(self, text)
            log.info("textarea", "输入: " .. text)
        end
    })
    y = y + 40 + 15     -- 间距15

    -- 2.2 进度条组件
    airui.label({
        parent = scroll_container,
        text = "进度条",
        x = 10,
        y = y,
        w = 300,
        h = 14,
        font_size = 12,
        color = 0x333333,
    })
    y = y + 14 + 5

    local progress_bar = airui.bar({
        parent = scroll_container,
        x = 10,
        y = y,
        w = 300,
        h = 16,
        value = 65,
        bg_color = 0xE0E0E0,
        indicator_color = 0x4CAF50,
        radius = 8,
        show_progress_text = true,
        progress_text_format = "%d%%",
    })
    y = y + 16 + 15

    -- 2.3 按钮组件（两个并排）
    local btn_container = airui.container({
        parent = scroll_container,
        x = 10,
        y = y,
        w = 300,
        h = 40,
        color = 0xFFFFFF,
    })

    local test_btn = airui.button({
        parent = btn_container,
        x = 0,
        y = 0,
        w = 145,
        h = 40,
        text = "更新进度",
        on_click = function()
            local current = progress_bar:get_value()
            local new_value = current + 10
            if new_value > 100 then new_value = 0 end
            progress_bar:set_value(new_value, true)
        end
    })

    local msgbox_btn = airui.button({
        parent = btn_container,
        x = 155,
        y = 0,
        w = 145,
        h = 40,
        text = "显示消息",
        on_click = function()
            local msgbox = airui.msgbox({
                title = "提示",
                text = "这是消息框演示\n点击确定关闭",
                buttons = { "确定", "取消" },
                on_action = function(self, label)
                    log.info("msgbox", "点击了: " .. label)
                    self:hide()
                end
            })
            msgbox:show()
        end
    })
    y = y + 40 + 15

    -- 2.4 开关组件
    airui.label({
        parent = scroll_container,
        text = "开关",
        x = 10,
        y = y,
        w = 300,
        h = 14,
        font_size = 12,
        color = 0x333333,
    })
    y = y + 14 + 5

    local is_on = true
    local toggle_switch = airui.switch({
        parent = scroll_container,
        x = 10,
        y = y,
        w = 60,
        h = 30,
        checked = true,
        on_change = function(self)
            is_on = not is_on
            log.info("switch", is_on and "开" or "关")
        end
    })
    y = y + 30 + 15

    -- 2.5 下拉框组件
    airui.label({
        parent = scroll_container,
        text = "下拉选择",
        x = 10,
        y = y,
        w = 300,
        h = 14,
        font_size = 12,
        color = 0x333333,
    })
    y = y + 14 + 5

    local dropdown = airui.dropdown({
        parent = scroll_container,
        x = 10,
        y = y,
        w = 300,
        h = 32,
        options = { "选项一", "选项二", "选项三", "选项四" },
        default_index = 0,
        on_change = function(self, index)
            local texts = { "选项一", "选项二", "选项三", "选项四" }
            log.info("dropdown", "选择了: " .. texts[index + 1])
        end
    })
    y = y + 32 + 15

    -- 2.6 表格组件（高度120，显示4行数据）
    airui.label({
        parent = scroll_container,
        text = "数据表格",
        x = 10,
        y = y,
        w = 300,
        h = 14,
        font_size = 12,
        color = 0x333333,
    })
    y = y + 14 + 5

    local data_table = airui.table({
        parent = scroll_container,
        x = 10,
        y = y,
        w = 300,
        h = 120,         -- 增高至120，可显示4行+表头
        rows = 4,
        cols = 3,
        col_width = { 100, 80, 100 },
        border_color = 0xCCCCCC
    })

    -- 设置表格内容（4行数据）
    data_table:set_cell_text(0, 0, "姓名")
    data_table:set_cell_text(0, 1, "年龄")
    data_table:set_cell_text(0, 2, "城市")
    data_table:set_cell_text(1, 0, "张三")
    data_table:set_cell_text(1, 1, "25")
    data_table:set_cell_text(1, 2, "北京")
    data_table:set_cell_text(2, 0, "李四")
    data_table:set_cell_text(2, 1, "30")
    data_table:set_cell_text(2, 2, "上海")
    data_table:set_cell_text(3, 0, "王五")
    data_table:set_cell_text(3, 1, "28")
    data_table:set_cell_text(3, 2, "广州")
    y = y + 120 + 15

    -- 2.7 图表组件
    airui.label({
        parent = scroll_container,
        text = "折线图示例",
        x = 10,
        y = y,
        w = 300,
        h = 14,
        font_size = 12,
        color = 0x333333,
    })
    y = y + 14 + 5

    local chart = airui.chart({
        parent = scroll_container,
        x = 10,
        y = y,
        w = 300,
        h = 90,          -- 高度90，更清晰
        type = "line",
        y_min = 0,
        y_max = 100,
        point_count = 60,
        line_width = 2,
        point_radius = 0,
        legend = false,
        x_axis = { enable = false },
        y_axis = { enable = false },
    })

    -- 添加一个系列，生成叠加波形
    local sid = chart:add_series({color = 0x00b4ff})

    y = y + 90 + 15

    -- 2.8 二维码组件
    airui.label({
        parent = scroll_container,
        text = "二维码",
        x = 10,
        y = y,
        w = 300,
        h = 14,
        font_size = 12,
        color = 0x333333,
    })
    y = y + 14 + 5

    local qrcode = airui.qrcode({
        parent = scroll_container,
        x = 110,         -- 水平居中 (320-100)/2 ≈ 110
        y = y,
        size = 100,
        data = "https://docs.openluat.com/",
        dark_color = 0x000000,
        light_color = 0xFFFFFF,
        quiet_zone = true,
    })
    y = y + 100 + 15


    -- 3. 虚拟键盘（底部固定）
    local keyboard = airui.keyboard({
        x = 0,
        y = -20,
        w = 320,
        h = 200,
        mode = "text",
        target = text_input,
        auto_hide = true,
        on_commit = function()
            log.info("input", "输入内容: ", text_input:get_text())
        end,
    })

    -- 4. 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 460,
        w = 320,
        h = 20,
        color = 0x333333,
    })

    airui.label({
        parent = status_bar,
        text = "AirUI Demo v1.1",
        x = 10,
        y = 2,
        w = 300,
        h = 16,
        color = 0xFFFFFF,
    })

        -- 动态更新循环
    local step = 0
    while true do
        step = step + 0.2
        -- 生成0~100的整数
        local val_sin = math.floor(50 + 50 * math.sin(step))
        chart:push(sid, val_sin)
        sys.wait(100)
    end

end

sys.taskInit(ui_main)