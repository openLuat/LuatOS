--[[
@module  input_page
@summary 输入框组件演示页面
@version 1.0
@date    2026.02.05
@author  江访
@usage
本文件是输入框组件的演示页面，展示输入框的各种用法。
]]

local input_page = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function input_page.create_ui()
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
        color = 0x3F51B5,
    })

    airui.label({
        parent = title_bar,
        text = "输入框组件演示",
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

    -- 示例1: 基本输入框
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本输入框",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
        font_size = 14,
    })

    -- 创建键盘并关联输入框（v1.0.3 推荐内嵌键盘配置）
    local basic_input = airui.textarea({
        parent = scroll_container,
        x = 20,
        y = 40,
        w = 280,
        h = 100,
        text = "",
        placeholder = "请输入文本...",
        max_len = 100,
        keyboard = {                    -- v1.0.3 内嵌键盘
            x = 0,
            y = -20,
            w = 320,
            h = 200,
            mode = "text",
            auto_hide = true,
        },
    })

    -- 示例2: 带默认值的输入框
    airui.label({
        parent = scroll_container,
        text = "示例2: 带默认值",
        x = 10,
        y = 160,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local default_input = airui.textarea({
        parent = scroll_container,
        x = 20,
        y = 190,
        w = 280,
        h = 60,
        text = "默认文本",
        placeholder = "请输入...",
        max_len = 50,
        keyboard = {                    -- 内嵌键盘
            x = 0,
            y = -20,
            w = 320,
            h = 200,
            mode = "text",
            auto_hide = true,
        },
    })

    -- 示例3: 数字输入框
    airui.label({
        parent = scroll_container,
        text = "示例3: 数字输入框",
        x = 10,
        y = 270,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local number_input = airui.textarea({
        parent = scroll_container,
        x = 20,
        y = 300,
        w = 280,
        h = 60,
        text = "",
        placeholder = "请输入数字...",
        max_len = 20,
        keyboard = {
            x = 0,
            y = 0,
            w = 320,
            h = 200,
            mode = "numeric",            -- 数字键盘
            auto_hide = true,
        },
    })

    airui.label({
        parent = scroll_container,
        text = "（使用数字键盘）",
        x = 20,
        y = 365,
        w = 280,
        h = 20,
        font_size = 12,
        color = 0x666666,
    })

    -- 示例4: 表单输入
    airui.label({
        parent = scroll_container,
        text = "示例4: 表单输入",
        x = 10,
        y = 400,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local form_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 430,
        w = 280,
        h = 150,
        color = 0xE8EAF6,
        radius = 8,
    })

    -- 姓名输入
    airui.label({
        parent = form_container,
        text = "姓名:",
        x = 10,
        y = 20,
        w = 60,
        h = 20,
        font_size = 14,
    })

    local name_input = airui.textarea({
        parent = form_container,
        x = 80,
        y = 15,
        w = 180,
        h = 30,
        text = "",
        placeholder = "请输入姓名",
        max_len = 20,
        keyboard = {                     -- 内嵌键盘
            x = 0,
            y = -20,
            w = 320,
            h = 200,
            mode = "text",
            auto_hide = true,
        },
    })

    -- 邮箱输入
    airui.label({
        parent = form_container,
        text = "邮箱:",
        x = 10,
        y = 60,
        w = 60,
        h = 20,
        font_size = 14,
    })

    local email_input = airui.textarea({
        parent = form_container,
        x = 80,
        y = 55,
        w = 180,
        h = 30,
        text = "",
        placeholder = "请输入邮箱",
        max_len = 50,
        keyboard = {                     -- 内嵌键盘
            x = 0,
            y = -20,
            w = 320,
            h = 200,
            mode = "text",
            auto_hide = true,
        },
    })

    -- 提交按钮
    local submit_btn = airui.button({
        parent = form_container,
        x = 80,
        y = 100,
        w = 120,
        h = 35,
        text = "提交",
        on_click = function(self)
            local name = name_input:get_text()
            local email = email_input:get_text()

            if name == "" or email == "" then
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
                    text = "提交成功!\n姓名: " .. name .. "\n邮箱: " .. email,
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

    -- 示例5: 输入框控制
    airui.label({
        parent = scroll_container,
        text = "示例5: 输入框控制",
        x = 10,
        y = 600,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local control_input = airui.textarea({
        parent = scroll_container,
        x = 20,
        y = 630,
        w = 200,
        h = 60,
        text = "可控制的输入框",
        placeholder = "请输入...",
        max_len = 50,
        keyboard = {                     -- 内嵌键盘
            x = 0,
            y = -20,
            w = 320,
            h = 200,
            mode = "text",
            auto_hide = true,
        },
    })

    -- 控制按钮
    local clear_btn = airui.button({
        parent = scroll_container,
        x = 230,
        y = 630,
        w = 70,
        h = 30,
        text = "清空",
        on_click = function(self)
            control_input:set_text("")
        end
    })

    local get_btn = airui.button({
        parent = scroll_container,
        x = 230,
        y = 670,
        w = 70,
        h = 30,
        text = "获取",
        on_click = function(self)
            local text = control_input:get_text()
            local msg = airui.msgbox({
                text = "当前内容: " .. text,
                buttons = { "确定" },
                timeout = 2000,
                on_action = function(self, label)
                    self:hide()
                end
            })
            msg:show()
        end
    })

    -- 设置光标位置
    local cursor_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 700,
        w = 130,
        h = 35,
        text = "光标到开头",
        on_click = function(self)
            control_input:set_cursor(0)
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 输入框支持文本监听和控制",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        font_size = 14,
    })
end

-- 初始化页面
function input_page.init(params)
    input_page.create_ui()
end

-- 清理页面
function input_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return input_page