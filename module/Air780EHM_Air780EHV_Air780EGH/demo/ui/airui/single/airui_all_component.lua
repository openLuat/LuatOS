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

    -- 创建主容器（竖屏尺寸）
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,    -- 改为320
        h = 480,    -- 保持480
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

    local title_label = airui.label({
        parent = title_bar,
        text = "AirUI组件演示",
        x = 10,
        y = 10,
        w = 300,
        h = 30,
    })

    -- 2. 内容区域（可滚动区域）
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 50,     -- 从标题栏下面开始
        w = 320,
        h = 380,    -- 为底部键盘留出空间
        color = 0xFFFFFF,
    })

    -- 2.1 文本输入框组件
    airui.label({
        parent = scroll_container,
        text = "文本输入",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
    })

    local text_input = airui.textarea({
        parent = scroll_container,
        x = 10,
        y = 35,
        w = 300,
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
        parent = scroll_container,
        text = "进度条",
        x = 10,
        y = 85,
        w = 100,
        h = 20,
    })

    local progress_bar = airui.bar({
        parent = scroll_container,
        x = 10,
        y = 110,
        w = 300,
        h = 15,
        value = 65,
        bg_color = 0xE0E0E0,
        indicator_color = 0x4CAF50,
        radius = 7,
    })

    -- 2.3 按钮组件 - 横向排列
    local btn_container = airui.container({
        parent = scroll_container,
        x = 10,
        y = 135,
        w = 300,
        h = 50,
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
            if new_value > 100 then
                new_value = 0
            end
            progress_bar:set_value(new_value, true)
            log.info("progress", "进度更新为: " .. new_value .. "%")
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
                timeout = 2000,
                on_action = function(self, label)
                    log.info("msgbox", "点击了: " .. label)
                end
            })
            msgbox:show()
        end
    })

    -- 2.4 开关组件
    local switch_container = airui.container({
        parent = scroll_container,
        x = 10,
        y = 195,
        w = 300,
        h = 40,
        color = 0xFFFFFF,
    })

    airui.label({
        parent = switch_container,
        text = "开关",
        x = 0,
        y = 10,
        w = 60,
        h = 20,
    })

    local is_on = true
    local toggle_switch = airui.switch({
        parent = switch_container,
        x = 70,
        y = 5,
        w = 60,
        h = 30,
        checked = true,
        on_change = function(self)
            is_on = not is_on
            if is_on then
                log.info("当前状态: 开")
            else
                log.info("当前状态: 关")
            end
        end
    })

    -- 2.5 下拉框组件
    airui.label({
        parent = scroll_container,
        text = "下拉选择",
        x = 10,
        y = 245,
        w = 100,
        h = 20,
    })

    local dropdown = airui.dropdown({
        parent = scroll_container,
        x = 10,
        y = 270,
        w = 300,
        h = 40,
        options = { "选项一", "选项二", "选项三", "选项四" },
        default_index = 0,
        on_change = function(self, index)
            local texts = { "选项一", "选项二", "选项三", "选项四" }
            log.info("dropdown", "选择了: " .. texts[index + 1])
        end
    })

    -- 2.6 表格组件
    airui.label({
        parent = scroll_container,
        text = "数据表格",
        x = 10,
        y = 320,
        w = 300,
        h = 20,
    })

    local data_table = airui.table({
        parent = scroll_container,
        x = 10,
        y = 345,
        w = 300,
        h = 120,
        rows = 3,
        cols = 3,
        col_width = { 100, 80, 100 },
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

    -- 3. 创建虚拟键盘（放在底部）
    local keyboard = airui.keyboard({
        x = 0,
        y = -20,  -- 距离底边10像素
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
        y = 460,  -- 从460位置开始
        w = 320,
        h = 20,
        color = 0x333333,
    })

    airui.label({
        parent = status_bar,
        text = "AirUI Demo v1.0",
        x = 10,
        y = 2,
        w = 300,
        h = 16,
    })

    -- 主循环,V1.0.3已不需要
    -- while true do
    --     airui.refresh()
    --     sys.wait(50)
    -- end
end

sys.taskInit(ui_main)