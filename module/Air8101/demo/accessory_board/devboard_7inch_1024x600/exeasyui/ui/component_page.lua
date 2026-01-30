--[[
@module  component_page
@summary exEasyUI组件演示页面模块，展示各种UI组件的使用方法
@version 1.0
@date    2026.01.26
@author  江访
@usage
本文件为组件演示页面功能模块，核心业务逻辑为：
1、创建带上下滚动功能的演示窗口；
2、展示进度条、消息框、按钮、复选框、输入框、下拉框、图片轮播等UI组件；
3、演示组件的交互功能和事件处理；
4、提供返回主页的导航功能；

本文件的对外接口有1个：
1、component_page.create(ui)：创建组件演示页面；
]]

local component_page = {}

--[[
创建组件演示页面；

@api component_page.create(ui)
@summary 创建组件演示页面界面
@table ui UI库对象
@return table 组件演示窗口对象

@usage
-- 在子页面工厂中调用创建组件演示页面
local component_page = require("component_page").create(ui)
]]
function component_page.create(ui)
    local win = ui.window({
        background_color = ui.COLOR_WHITE,
        x = 0,
        y = 0,
        w = 1024,
        h = 600 -- 全屏窗口
    })

    -- 启用滚动
    win:enable_scroll({
        direction = "vertical",
        content_height = 800,
        threshold = 10
    })

    -- 标题 - 居中
    local title = ui.label({
        x = 400,
        y = 30,
        text = "组件演示页面",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 返回按钮
    local btn_back = ui.button({
        x = 30,
        y = 25,
        w = 100,
        h = 45,
        text = "返回",
        text_size = 16,
        on_click = function()
            win:back()
        end
    })

    -- ==================== 布局参数 ====================
    local column1_x = 50   -- 第一列起始位置
    local column2_x = 540  -- 第二列起始位置（1024宽度分两列）
    local start_y = 100
    local spacing_y = 60

    -- ==================== 1. 进度条组件演示 ====================
    local progress_label = ui.label({
        x = column1_x,
        y = start_y,
        text = "1. 进度条组件:",
        color = ui.COLOR_BLACK,
        size = 18
    })

    local progress_value = 0
    local progress_bar = ui.progress_bar({
        x = column1_x,
        y = start_y + 35,
        w = 300,
        h = 35,
        progress = progress_value
    })

    local btn_progress = ui.button({
        x = column1_x + 310,
        y = start_y + 35,
        w = 120,
        h = 35,
        text = "+10%",
        on_click = function()
            progress_value = progress_value + 10
            if progress_value > 100 then
                progress_value = 0
            end
            progress_bar:set_progress(progress_value)
            progress_bar:set_text("进度: " .. progress_value .. "%")
        end
    })

    -- ==================== 2. 输入框组件演示 ====================
    local input_label = ui.label({
        x = column1_x,
        y = start_y + spacing_y + 50,
        text = "2. 输入框组件:",
        color = ui.COLOR_BLACK,
        size = 18
    })

    -- 普通文本输入框
    local text_input = ui.input({
        x = column1_x,
        y = start_y + spacing_y + 85,
        w = 450,
        h = 45,
        placeholder = "请输入文本...",
        max_length = 20
    })

    -- 密码输入框
    local password_input = ui.input({
        x = column1_x,
        y = start_y + spacing_y + 140,
        w = 450,
        h = 45,
        placeholder = "请输入密码...",
        input_type = "password",
        max_length = 16
    })

    -- 数字输入框
    local number_input = ui.input({
        x = column1_x,
        y = start_y + spacing_y + 195,
        w = 450,
        h = 45,
        placeholder = "请输入数字...",
        input_type = "number",
        max_length = 16
    })

    -- ==================== 3. 按钮组件演示 ====================
    local button_label = ui.label({
        x = column1_x,
        y = start_y + spacing_y * 2 + 240,
        text = "3. 按钮组件:",
        color = ui.COLOR_BLACK,
        size = 18
    })

    -- 普通按钮
    local normal_btn = ui.button({
        x = column1_x,
        y = start_y + spacing_y * 2 + 275,
        w = 120,
        h = 45,
        text = "普通按钮",
        on_click = function()
            log.info("component_page", "普通按钮被点击")
        end
    })

    -- 带颜色的按钮
    local colored_btn = ui.button({
        x = column1_x + 130,
        y = start_y + spacing_y * 2 + 275,
        w = 120,
        h = 45,
        text = "蓝色按钮",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            log.info("component_page", "蓝色按钮被点击")
        end
    })

    -- 图片按钮
    local image_btn = ui.button({
        x = column1_x + 260,
        y = start_y + spacing_y * 2 + 265,
        w = 75,
        h = 75,
        src = "/luadb/4.jpg",
        src_toggled = "/luadb/5.jpg",
        toggle = true,
        on_click = function()
            log.info("component_page", "图片按钮被点击")
        end
    })
    -- ==================== 4. 复选框组件演示 ====================
    local checkbox_label = ui.label({
        x = column2_x,
        y = start_y,
        text = "4. 复选框组件:",
        color = ui.COLOR_BLACK,
        size = 18
    })

    local checkbox1 = ui.check_box({
        x = column2_x,
        y = start_y + 40,
        text = "选项A",
        checked = false,
        on_change = function(checked)
            log.info("component_page", "选项A:", checked)
        end
    })

    local checkbox2 = ui.check_box({
        x = column2_x + 120,
        y = start_y + 40,
        text = "选项B",
        checked = true,
        on_change = function(checked)
            log.info("component_page", "选项B:", checked)
        end
    })

    -- ==================== 5. 下拉框组件演示 ====================
    local combo_label = ui.label({
        x = column2_x,
        y = start_y + spacing_y + 35,
        text = "5. 下拉框组件:",
        color = ui.COLOR_BLACK,
        size = 18
    })

    local combo_box = ui.combo_box({
        x = column2_x,
        y = start_y + spacing_y + 70,
        w = 450,
        h = 45,
        options = { "选项1", "选项2", "选项3", "选项4", "选项5" },
        placeholder = "请选择",
        selected = 1,
        on_select = function(value, index, text)
            log.info("component_page", "选择了:", text, "索引:", index)
        end
    })

    -- ==================== 6. 消息框组件演示 ====================
    local msgbox_label = ui.label({
        x = column2_x,
        y = start_y + spacing_y * 2 + 75,
        text = "6. 消息框组件:",
        color = ui.COLOR_BLACK,
        size = 18
    })

    local btn_msgbox = ui.button({
        x = column2_x,
        y = start_y + spacing_y * 2 + 110,
        w = 180,
        h = 45,
        text = "弹出消息框",
        on_click = function()
            local message_box = ui.message_box({
                x = 312,
                y = 200, -- 居中显示
                w = 500,
                h = 250,
                title = "提示",
                message = "这是一个exEasyUI消息框演示",
                buttons = { "确定", "取消" },
                on_result = function(button_index)
                    log.info("component_page", "点击了按钮:", button_index)
                end
            })
            ui.add(message_box)
        end
    })

    -- ==================== 7. 图片轮播组件演示 ====================
    local picture_label = ui.label({
        x = column2_x,
        y = start_y + spacing_y * 3 + 110,
        text = "7. 图片轮播组件:",
        color = ui.COLOR_BLACK,
        size = 18
    })

    local picture = ui.picture({
        x = column2_x,
        y = start_y + spacing_y * 3 + 145,
        w = 580,
        h = 180, -- 增大尺寸
        sources = { "/luadb/1.jpg", "/luadb/2.jpg", "/luadb/3.jpg" },
        autoplay = true,
        interval = 2000
    })

    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(progress_label)
    win:add(progress_bar)
    win:add(btn_progress)
    win:add(checkbox_label)
    win:add(checkbox1)
    win:add(checkbox2)
    win:add(input_label)
    win:add(text_input)
    win:add(password_input)
    win:add(number_input)
    win:add(combo_label)
    win:add(combo_box)
    win:add(button_label)
    win:add(normal_btn)
    win:add(colored_btn)
    win:add(image_btn)
    win:add(msgbox_label)
    win:add(btn_msgbox)
    win:add(picture_label)
    win:add(picture)

    return win
end

return component_page