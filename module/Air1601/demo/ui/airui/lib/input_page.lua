--[[
@module  input_page
@summary 输入框组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是输入框组件的演示页面，展示输入框的各种用法。
]]

local input_page = {}

-- 页面UI元素
local main_container = nil
local keyboards = {}

-- 创建UI
function input_page.create_ui()
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
        color = 0x3F51B5,
    })

    airui.label({
        parent = title_bar,
        text = "输入框组件演示",
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
    local section_height = 120

    -- 示例1: 基本输入框（左列）
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本输入框",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local basic_input = airui.textarea({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 80,
        text = "",
        placeholder = "请输入文本内容...",
        max_len = 100,
        size = 16,
    })

    -- 示例2: 带默认值的输入框（右列）
    airui.label({
        parent = scroll_container,
        text = "示例2: 带默认值的输入框",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local default_input = airui.textarea({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 80,
        text = "这是默认文本",
        placeholder = "请输入...",
        max_len = 80,
        size = 16,
    })

    y_offset = y_offset + section_height

    -- 示例3: 多行输入框（左列）
    airui.label({
        parent = scroll_container,
        text = "示例3: 多行输入框",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local multiline_input = airui.textarea({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 120,
        text = "",
        placeholder = "请输入多行文本内容...\n支持换行输入",
        max_len = 200,
        size = 16,
    })

    -- 示例4: 数字输入框（右列）
    airui.label({
        parent = scroll_container,
        text = "示例4: 数字输入框",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local number_input = airui.textarea({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 80,
        text = "",
        placeholder = "请输入数字...",
        max_len = 20,
        size = 16,
    })

    y_offset = y_offset + 160

    -- 示例5: 表单输入（左列）
    airui.label({
        parent = scroll_container,
        text = "示例5: 表单输入",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local form_container = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 250,
        color = 0xE8EAF6,
        radius = 12,
    })

    -- 姓名输入
    airui.label({
        parent = form_container,
        text = "姓名:",
        x = 30,
        y = 30,
        w = 80,
        h = 35,
        size = 16,
    })

    local name_input = airui.textarea({
        parent = form_container,
        x = 120,
        y = 25,
        w = 280,
        h = 40,
        text = "",
        placeholder = "请输入姓名",
        max_len = 20,
        size = 16,
    })

    -- 邮箱输入
    airui.label({
        parent = form_container,
        text = "邮箱:",
        x = 30,
        y = 85,
        w = 80,
        h = 35,
        size = 16,
    })

    local email_input = airui.textarea({
        parent = form_container,
        x = 120,
        y = 80,
        w = 280,
        h = 40,
        text = "",
        placeholder = "请输入邮箱地址",
        max_len = 50,
        size = 16,
    })

    -- 电话输入
    airui.label({
        parent = form_container,
        text = "电话:",
        x = 30,
        y = 140,
        w = 80,
        h = 35,
        size = 16,
    })

    local phone_input = airui.textarea({
        parent = form_container,
        x = 120,
        y = 135,
        w = 280,
        h = 40,
        text = "",
        placeholder = "请输入电话号码",
        max_len = 20,
        size = 16,
    })

    -- 提交按钮
    local submit_btn = airui.button({
        parent = form_container,
        x = 120,
        y = 195,
        w = 280,
        h = 45,
        text = "提交表单",
        size = 16,
        on_click = function()
            local name = name_input:get_text()
            local email = email_input:get_text()
            local phone = phone_input:get_text()

            if name == "" or email == "" or phone == "" then
                local msg = airui.msgbox({
                    text = "请填写完整信息",
                    buttons = { "确定" },
                    on_action = function(self, label)
                        if label == "确定" then
                            self:hide()
                        end
                    end
                })
                msg:show()
            else
                local msg = airui.msgbox({
                    text = "提交成功!\n姓名: " .. name .. "\n邮箱: " .. email .. "\n电话: " .. phone,
                    buttons = { "确定" },
                    on_action = function(self, label)
                        if label == "确定" then
                            self:hide()
                        end
                    end
                })
                msg:show()
            end
        end
    })

    -- 示例6: 输入框控制（右列）
    airui.label({
        parent = scroll_container,
        text = "示例6: 输入框控制",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local control_container = airui.container({
        parent = scroll_container,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 440,
        h = 250,
        color = 0xF3E5F5,
        radius = 12,
    })

    local control_input = airui.textarea({
        parent = control_container,
        x = 30,
        y = 30,
        w = 380,
        h = 80,
        text = "这是一个可控制的输入框",
        placeholder = "请输入...",
        max_len = 100,
        size = 16,
    })

    -- 控制按钮区域
    local control_btn_y = 130
    local control_btn_width = 120
    
    -- 清空按钮
    local clear_btn = airui.button({
        parent = control_container,
        x = 30,
        y = control_btn_y,
        w = control_btn_width,
        h = 40,
        text = "清空内容",
        size = 14,
        on_click = function()
            control_input:set_text("")
        end
    })

    -- 获取按钮
    local get_btn = airui.button({
        parent = control_container,
        x = 170,
        y = control_btn_y,
        w = control_btn_width,
        h = 40,
        text = "获取内容",
        size = 14,
        on_click = function()
            local text = control_input:get_text()
            local msg = airui.msgbox({
                text = "当前内容: " .. text,
                buttons = { "确定" },
                timeout = 2000
            })
            msg:show()
        end
    })

    -- 设置内容按钮
    local set_btn = airui.button({
        parent = control_container,
        x = 310,
        y = control_btn_y,
        w = control_btn_width,
        h = 40,
        text = "设置内容",
        size = 14,
        on_click = function()
            control_input:set_text("这是新设置的内容 " .. os.date("%H:%M:%S"))
        end
    })

    -- 第二行控制按钮
    control_btn_y = control_btn_y + 50
    
    -- 禁用按钮
    local disable_btn = airui.button({
        parent = control_container,
        x = 30,
        y = control_btn_y,
        w = control_btn_width,
        h = 40,
        text = "禁用输入",
        size = 14,
        on_click = function()
            -- 这里需要根据AirUI的API来实现禁用功能
            log.info("input", "禁用输入框")
        end
    })

    -- 启用按钮
    local enable_btn = airui.button({
        parent = control_container,
        x = 170,
        y = control_btn_y,
        w = control_btn_width,
        h = 40,
        text = "启用输入",
        size = 14,
        on_click = function()
            -- 这里需要根据AirUI的API来实现启用功能
            log.info("input", "启用输入框")
        end
    })

    -- 隐藏按钮
    local hide_btn = airui.button({
        parent = control_container,
        x = 310,
        y = control_btn_y,
        w = control_btn_width,
        h = 40,
        text = "隐藏键盘",
        size = 14,
        on_click = function()
            for _, kb in ipairs(keyboards) do
                if kb then
                    kb:hide()
                end
            end
        end
    })

    -- 创建键盘
    local keyboard1 = airui.keyboard({
        x = 150,
        y = 350,
        w = 724,
        h = 220,
        mode = "text",
        target = basic_input,
        auto_hide = true,
    })
    table.insert(keyboards, keyboard1)

    local keyboard2 = airui.keyboard({
        x = 150,
        y = 350,
        w = 724,
        h = 220,
        mode = "text",
        target = default_input,
        auto_hide = true,
    })
    table.insert(keyboards, keyboard2)

    local keyboard3 = airui.keyboard({
        x = 150,
        y = 350,
        w = 724,
        h = 220,
        mode = "number",
        target = number_input,
        auto_hide = true,
    })
    keyboard3:set_layout("number")
    table.insert(keyboards, keyboard3)

    local keyboard4 = airui.keyboard({
        x = 150,
        y = 350,
        w = 724,
        h = 220,
        mode = "text",
        target = name_input,
        auto_hide = true,
    })
    table.insert(keyboards, keyboard4)

    local keyboard5 = airui.keyboard({
        x = 150,
        y = 350,
        w = 724,
        h = 220,
        mode = "text",
        target = control_input,
        auto_hide = true,
    })
    table.insert(keyboards, keyboard5)

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 输入框支持文本监听、键盘输入和动态控制",
        x = 20,
        y = 560,
        w = 500,
        h = 25,
        size = 14,
    })
end

-- 初始化页面
function input_page.init(params)
    keyboards = {}
    input_page.create_ui()
end

-- 清理页面
function input_page.cleanup()
    -- 清理所有键盘
    for _, kb in ipairs(keyboards) do
        if kb then
            kb:hide()
        end
    end
    keyboards = {}
    
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return input_page