--[[
@module  win_all_component
@summary 所有UI组件综合演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为所有UI组件综合演示模块，核心业务逻辑为：
1、创建带滚动功能的窗口容器；
2、集成展示所有exEasyUI组件；
3、实现组件间的交互逻辑；
4、展示进度条、消息框、按钮、复选框、输入框等完整功能；
5、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local function ui_main()

    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器并启用滚动
    local page1 = ui.window({ background_color = ui.COLOR_WHITE })
    page1:enable_scroll({
        direction = "vertical",
        content_height = 600,
        threshold = 8
    })

    -- ==================== 标题区域 ====================
    local title = ui.label({
        x = 250, y = 25,
        text = "所有UI组件综合演示",
        color = ui.COLOR_BLACK,
        size = 24
    })
    page1:add(title)

    -- 左列和右列布局
    local left_column_x = 50
    local right_column_x = 450
    local current_y = 80

    -- ==================== 左列：基础组件 ====================

    -- 进度条组件
    local progress_label = ui.label({
        x = left_column_x, y = current_y,
        text = "1. 进度条组件",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(progress_label)

    local progress = 50
    local pb = ui.progress_bar({
        x = left_column_x, y = current_y + 30,
        w = 300, h = 26,
        progress = progress
    })
    page1:add(pb)

    local btn_progress = ui.button({
        x = left_column_x + 310, y = current_y + 30,
        w = 80, h = 26,
        text = "+10%",
        size = 14,
        on_click = function(self)
            progress = progress + 10
            if progress > 100 then progress = 0 end
            pb:set_progress(progress)
        end
    })
    page1:add(btn_progress)

    current_y = current_y + 80

    -- 消息框按钮
    local msgbox_label = ui.label({
        x = left_column_x, y = current_y,
        text = "2. 消息框组件",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(msgbox_label)

    local btn_msgbox = ui.button({
        x = left_column_x, y = current_y + 30,
        w = 150, h = 40,
        text = "弹出消息框",
        size = 16,
        on_click = function()
            local message_box = ui.message_box({
                x = 150, y = 150,
                w = 500, h = 200,
                wordWrap = true,
                title = "综合演示",
                message = "这是所有UI组件的综合演示页面，展示了exEasyUI的各种组件功能。",
                buttons = { "确定", "取消" }
            })
            ui.add(message_box)
        end
    })
    page1:add(btn_msgbox)

    current_y = current_y + 90

    -- 切换按钮
    local toggle_label = ui.label({
        x = left_column_x, y = current_y,
        text = "3. 切换按钮",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(toggle_label)

    local btn_toggle = ui.button({
        x = left_column_x, y = current_y + 30,
        w = 80, h = 80,
        src = "/luadb/4.jpg",
        src_toggled = "/luadb/5.jpg",
        toggle = true,
    })
    page1:add(btn_toggle)

    current_y = current_y + 130

    -- 复选框
    local checkbox_label = ui.label({
        x = left_column_x, y = current_y,
        text = "4. 复选框组件",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(checkbox_label)

    local checkbox1 = ui.check_box({
        x = left_column_x, y = current_y + 30,
        text = "选项A",
        checked = false,
        size = 16,
        on_change = function(checked)
            log.info("checkbox", "选项A:", checked)
        end
    })
    page1:add(checkbox1)

    local checkbox2 = ui.check_box({
        x = left_column_x + 120, y = current_y + 30,
        text = "选项B",
        checked = true,
        size = 16,
        on_change = function(checked)
            log.info("checkbox", "选项B:", checked)
        end
    })
    page1:add(checkbox2)

    current_y = current_y + 80

    -- 文本输入框
    local input_label = ui.label({
        x = left_column_x, y = current_y,
        text = "5. 文本输入框",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(input_label)

    local text_input = ui.input({
        x = left_column_x, y = current_y + 30,
        w = 250, h = 35,
        placeholder = "请输入文本...",
        max_length = 20,
        size = 16
    })
    page1:add(text_input)

    current_y = current_y + 85

    -- ==================== 右列：高级组件 ====================
    local right_current_y = 80

    -- 密码输入框
    local password_label = ui.label({
        x = right_column_x, y = right_current_y,
        text = "6. 密码输入框",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(password_label)

    local password_input = ui.input({
        x = right_column_x, y = right_current_y + 30,
        w = 200, h = 35,
        placeholder = "请输入密码...",
        input_type = "password",
        max_length = 16,
        size = 16
    })
    page1:add(password_input)

    local password_visible = false
    local btn_password_toggle = ui.button({
        x = right_column_x + 210, y = right_current_y + 30,
        w = 80, h = 35,
        text = "显示",
        size = 14,
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            password_visible = not password_visible
            password_input.input_type = password_visible and "text" or "password"
            btn_password_toggle:set_text(password_visible and "隐藏" or "显示")
        end
    })
    page1:add(btn_password_toggle)

    right_current_y = right_current_y + 85

    -- 数字输入框
    local number_label = ui.label({
        x = right_column_x, y = right_current_y,
        text = "7. 数字输入框",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(number_label)

    local number_input = ui.input({
        x = right_column_x, y = right_current_y + 30,
        w = 120, h = 35,
        placeholder = "0-100",
        input_type = "number",
        max_length = 3,
        size = 16
    })
    page1:add(number_input)

    local btn_number_minus = ui.button({
        x = right_column_x + 130, y = right_current_y + 30,
        w = 40, h = 35,
        text = "-",
        size = 16,
        on_click = function()
            local value = tonumber(number_input:get_text()) or 0
            if value > 0 then
                number_input:set_text(tostring(value - 1))
            end
        end
    })
    page1:add(btn_number_minus)

    local btn_number_plus = ui.button({
        x = right_column_x + 180, y = right_current_y + 30,
        w = 40, h = 35,
        text = "+",
        size = 16,
        on_click = function()
            local value = tonumber(number_input:get_text()) or 0
            if value < 100 then
                number_input:set_text(tostring(value + 1))
            end
        end
    })
    page1:add(btn_number_plus)

    right_current_y = right_current_y + 85

    -- 下拉框
    local combo_label = ui.label({
        x = right_column_x, y = right_current_y,
        text = "8. 下拉框组件",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(combo_label)

    local combo_box = ui.combo_box({
        x = right_column_x, y = right_current_y + 30,
        w = 200, h = 35,
        options = { "选项1", "选项2", "选项3", "选项4" },
        placeholder = "请选择",
        selected = 1,
        size = 16,
        on_select = function(value, index, text)
            log.info("combo_box", "选择了:", text, "索引:", index)
        end
    })
    page1:add(combo_box)

    right_current_y = right_current_y + 85

    -- 图片轮播
    local picture_label = ui.label({
        x = right_column_x, y = right_current_y,
        text = "9. 图片轮播",
        color = ui.COLOR_BLACK,
        size = 18
    })
    page1:add(picture_label)

    local pic = ui.picture({
        x = right_column_x, y = right_current_y + 30,
        w = 200, h = 150,
        sources = { "/luadb/1.jpg", "/luadb/2.jpg", "/luadb/3.jpg" },
        autoplay = true,
        interval = 2000
    })
    page1:add(pic)

    local btn_picture_toggle = ui.button({
        x = right_column_x, y = right_current_y + 190,
        w = 100, h = 35,
        text = "下一张",
        size = 14,
        on_click = function()
            pic:next()
        end
    })
    page1:add(btn_picture_toggle)

    -- 底部提示
    local hint = ui.label({
        x = 250, y = 1650,
        text = "上下滚动查看更多组件",
        color = ui.COLOR_GRAY,
        size = 16
    })
    page1:add(hint)

    -- 注册窗口到UI系统
    ui.add(page1)

end

sys.taskInit(ui_main)