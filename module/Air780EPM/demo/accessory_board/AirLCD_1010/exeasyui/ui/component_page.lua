--[[
@module  component_page
@summary exEasyUI组件演示页面模块，展示各种UI组件的使用方法
@version 1.0
@date    2025.12.10
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
        w = 320,
        h = 480
    })

    -- 启用滚动
    win:enable_scroll({
        direction = "vertical",
        content_height = 800,
        threshold = 10
    })

    -- 标题
    local title = ui.label({
        x = 120,
        y = 25,
        text = "Component Demo Page",
        color = ui.COLOR_BLACK,
        size = 12
    })

    -- 返回按钮
    local btn_back = ui.button({
        x = 20,
        y = 20,
        w = 60,
        h = 30,
        text = "Back",
        on_click = function()
            win:back()
        end
    })

    -- ==================== 1. 进度条组件演示 ====================
    local progress_label = ui.label({
        x = 20,
        y = 70,
        text = "1. Progress Bar:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    local progress_value = 0
    local progress_bar = ui.progress_bar({
        x = 20,
        y = 100,
        w = 200,
        h = 26,
        progress = progress_value
    })

    local btn_progress = ui.button({
        x = 230,
        y = 100,
        w = 70,
        h = 26,
        text = "+10%",
        on_click = function()
            progress_value = progress_value + 10
            if progress_value > 100 then
                progress_value = 0
            end
            progress_bar:set_progress(progress_value)
            progress_bar:set_text("Progress: " .. progress_value .. "%")
        end
    })

    -- ==================== 2. 消息框组件演示 ====================
    local msgbox_label = ui.label({
        x = 20,
        y = 140,
        text = "2. Message Box:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    local btn_msgbox = ui.button({
        x = 20,
        y = 170,
        w = 180,
        h = 30,
        text = "Show MessageBox",
        on_click = function()
            local message_box = ui.message_box({
                x = 10,
                y = 100,
                w = 300,
                h = 150,
                title = "Info",
                message = "This is an exEasyUI message box demo",
                buttons = { "OK", "Cancel" },
                on_result = function(button_index)
                    log.info("component_page", "Button clicked:", button_index)
                end
            })
            ui.add(message_box)
        end
    })

    -- ==================== 3. 复选框组件演示 ====================
    local checkbox_label = ui.label({
        x = 20,
        y = 220,
        text = "3. Check Box:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    local checkbox1 = ui.check_box({
        x = 20,
        y = 250,
        text = "Option A",
        checked = false,
        on_change = function(checked)
            log.info("component_page", "Option A:", checked)
        end
    })

    local checkbox2 = ui.check_box({
        x = 120,
        y = 250,
        text = "Option B",
        checked = true,
        on_change = function(checked)
            log.info("component_page", "Option B:", checked)
        end
    })

    -- ==================== 4. 输入框组件演示 ====================
    local input_label = ui.label({
        x = 20,
        y = 300,
        text = "4. Input Box:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    -- 普通文本输入框
    local text_input = ui.input({
        x = 20,
        y = 330,
        w = 200,
        h = 30,
        placeholder = "Enter text...",
        max_length = 20
    })

    -- 密码输入框
    local password_input = ui.input({
        x = 20,
        y = 370,
        w = 200,
        h = 30,
        placeholder = "Enter password...",
        input_type = "password",
        max_length = 16
    })

    -- 数字输入框
    local number_input = ui.input({
        x = 20,
        y = 410,
        w = 200,
        h = 30,
        placeholder = "Enter number...",
        input_type = "number",
        max_length = 10
    })

    -- ==================== 5. 下拉框组件演示 ====================
    local combo_label = ui.label({
        x = 20,
        y = 460,
        text = "5. Combo Box:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    local combo_box = ui.combo_box({
        x = 20,
        y = 490,
        w = 200,
        h = 30,
        options = { "Option 1", "Option 2", "Option 3" },
        placeholder = "Please select",
        selected = 1,
        on_select = function(value, index, text)
            log.info("component_page", "Selected:", text, "Index:", index)
        end
    })

    -- ==================== 6. 图片轮播组件演示 ====================
    local picture_label = ui.label({
        x = 20,
        y = 540,
        text = "6. Image Carousel:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    local picture = ui.picture({
        x = 20,
        y = 570,
        w = 280,
        h = 100,
        sources = { "/luadb/1.jpg", "/luadb/2.jpg", "/luadb/3.jpg" },
        autoplay = true,
        interval = 2000
    })

    -- ==================== 7. 按钮组件演示 ====================
    local button_label = ui.label({
        x = 20,
        y = 705,
        text = "7. Buttons:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    -- 普通按钮
    local normal_btn = ui.button({
        x = 20,
        y = 735,
        w = 120,
        h = 30,
        text = "Normal Button",
        on_click = function()
            log.info("component_page", "Normal button clicked")
        end
    })

    -- 带颜色的按钮
    local colored_btn = ui.button({
        x = 150,
        y = 735,
        w = 90,
        h = 30,
        text = "Blue Button",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            log.info("component_page", "Blue button clicked")
        end
    })

    -- 图片按钮
    local image_btn = ui.button({
        x = 250,
        y = 720,
        w = 64,
        h = 64,
        src = "/luadb/4.jpg",
        src_toggled = "/luadb/5.jpg",
        toggle = true,
        on_click = function()
            log.info("component_page", "Image button clicked")
        end
    })


    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(progress_label)
    win:add(progress_bar)
    win:add(btn_progress)
    win:add(msgbox_label)
    win:add(btn_msgbox)
    win:add(checkbox_label)
    win:add(checkbox1)
    win:add(checkbox2)
    win:add(input_label)
    win:add(text_input)
    win:add(password_input)
    win:add(number_input)
    win:add(combo_label)
    win:add(combo_box)
    win:add(picture_label)
    win:add(picture)
    win:add(button_label)
    win:add(normal_btn)
    win:add(colored_btn)
    win:add(image_btn)

    return win
end

return component_page