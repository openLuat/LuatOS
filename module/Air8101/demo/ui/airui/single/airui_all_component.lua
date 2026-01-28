--[[
@module all_component_page
@summary 所有组件综合演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示所有AirUI组件的综合用法，展示完整UI界面。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 加载中文字体
    airui.font_load({
        type = "hzfont",
        path = nil,
        size = 16,
        cache_size = 2048,
        antialias = 4,
    })

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
        h = 390,
        color = 0xFFFFFF,
        radius = 8,
    })



    -- 2.1 文本输入框组件（移动到上方）
    airui.label({
        parent = left_col,
        text = "文本输入",
        x = 20,
        y = 20,
        w = 100,
        h = 25,
    })

    local text_input = airui.textarea({
        parent = left_col,
        x = 20,
        y = 50,
        w = 340,
        h = 40,
        max_len = 50,
        text = "示例文本",
        placeholder = "请输入...",
        on_text_change = function(self, text)
            log.info("textarea", "输入: " .. text)
        end
    })

    -- 2.2 进度条组件
    airui.label({
        parent = left_col,
        text = "进度条",
        x = 20,
        y = 110,
        w = 100,
        h = 25,
    })

    local progress_bar = airui.bar({
        parent = left_col,
        x = 20,
        y = 140,
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
        y = 180,
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

    -- 2.6 消息框按钮
    local msgbox_btn = airui.button({
        parent = left_col,
        x = 200,
        y = 180,
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
                end
            })
            msgbox:show()
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

    -- 2.4 开关组件
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
            -- 根据状态更新文本
            if is_on then
                log.info("当前状态: 开")
            else
                log.info("当前状态: 关")
            end
 
        end
    })

    -- 3. 右列组件
    local right_col = airui.container({
        parent = main_container,
        x = 420,
        y = 70,
        w = 360,
        h = 390,
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

    local data_table = airui.table({
        parent = right_col,
        x = 20,
        y = 60,
        w = 320,
        h = 250,
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

    -- 创建虚拟键盘
    local keyboard = airui.keyboard({
        x = 0,
        y = -20, -- 底部留20像素边距
        w = 800,
        h = 250,
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
        w = 800,
        h = 20,
        color = 0x333333,
    })

    airui.label({
        parent = status_bar,
        text = "AirUI Demo v1.0",
        x = 20,
        y = 2,
        w = 760,
        h = 16,
    })

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)