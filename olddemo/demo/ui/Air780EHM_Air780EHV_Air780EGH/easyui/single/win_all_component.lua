--[[
@module  win_all_component
@summary 所有UI组件综合演示模块
@version 1.0.0
@date    2025.11.28
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
        content_height = 1000,
        threshold = 8
    })

    -- ==================== 标题区域 ====================
    local title = ui.label({
        x = 100, y = 25,
        text = "组件演示页面",
        color = ui.COLOR_BLACK,
        size = 16
    })
    page1:add(title)

    -- ==================== 进度条组件区域 ====================
    local progress_label = ui.label({
        x = 20, y = 70,
        text = "1. 进度条组件演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local progress = 0
    local pb = ui.progress_bar({
        x = 20, y = 100,
        w = 200, h = 26,
        progress = progress
    })

    local btn_progress = ui.button({
        x = 230, y = 100,
        w = 70, h = 26,
        text = "+10%",
        on_click = function(self)
            progress = progress + 10
            if progress > 100 then
                progress = 0
            end
            pb:set_progress(progress)
            pb:set_text("进度: " .. progress .. "%")
        end
    })

    page1:add(progress_label)
    page1:add(pb)
    page1:add(btn_progress)

    -- ==================== 消息框组件区域 ====================
    local msgbox_label = ui.label({
        x = 20, y = 140,
        text = "2. 消息框组件演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local btn_msgbox = ui.button({
        x = 20, y = 170,
        w = 120, h = 30,
        text = "弹出消息框",
        on_click = function(self)
            local message_box = ui.message_box({
                x = 40, y = 150,
                w = 240, h = 180,
                wordWrap = true,
                title = "祝福",
                message = "愿你前路浩荡,未来可期.愿你保持热爱,奔赴山海。愿你所有的努力都不被辜负,最终活成自己最喜欢的模样.加油!",
                buttons = { "接受祝福" }
            })
            ui.add(message_box)
        end
    })

    page1:add(msgbox_label)
    page1:add(btn_msgbox)

    -- ==================== 切换按钮组件区域 ====================
    local toggle_label = ui.label({
        x = 20, y = 220,
        text = "3. 切换按钮演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local btn_toggle = ui.button({
        x = 20, y = 250,
        w = 64, h = 64,
        src = "/luadb/4.jpg",
        src_toggled = "/luadb/5.jpg",
        toggle = true,
    })

    page1:add(toggle_label)
    page1:add(btn_toggle)

    -- ==================== 复选框组件区域 ====================
    local checkbox_label = ui.label({
        x = 20, y = 330,
        text = "4. 复选框组件演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local checkbox1 = ui.check_box({
        x = 20, y = 360,
        text = "选项A",
        checked = false,
        on_change = function(checked)
            log.info("checkbox", "选项A:", checked)
        end
    })

    local checkbox2 = ui.check_box({
        x = 120, y = 360,
        text = "选项B",
        checked = true,
        on_change = function(checked)
            log.info("checkbox", "选项B:", checked)
        end
    })

    page1:add(checkbox_label)
    page1:add(checkbox1)
    page1:add(checkbox2)

    -- ==================== 输入框组件区域 ====================
    local input_label = ui.label({
        x = 20, y = 410,
        text = "5. 输入框组件演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local text_input = ui.input({
        x = 20, y = 440,
        w = 200, h = 30,
        placeholder = "请输入文本...",
        max_length = 20
    })

    page1:add(input_label)
    page1:add(text_input)

    -- ==================== 密码输入框组件区域 ====================
    local password_label = ui.label({
        x = 20, y = 490,
        text = "6. 密码输入框演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local password_input = ui.input({
        x = 20, y = 520,
        w = 150, h = 30,
        placeholder = "请输入密码...",
        input_type = "password",
        max_length = 16
    })

    local password_visible = false
    local btn_password_toggle = ui.button({
        x = 180, y = 520,
        w = 60, h = 30,
        text = "显示",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            password_visible = not password_visible
            password_input.input_type = password_visible and "text" or "password"
            btn_password_toggle:set_text(password_visible and "隐藏" or "显示")
        end
    })

    page1:add(password_label)
    page1:add(password_input)
    page1:add(btn_password_toggle)

    -- ==================== 数字输入框组件区域 ====================
    local number_label = ui.label({
        x = 20, y = 570,
        text = "7. 数字输入框演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local number_input = ui.input({
        x = 20, y = 600,
        w = 100, h = 30,
        placeholder = "0-100",
        input_type = "number",
        max_length = 3
    })

    local btn_number_minus = ui.button({
        x = 130, y = 600,
        w = 40, h = 30,
        text = "-",
        on_click = function()
            local value = tonumber(number_input:get_text()) or 0
            if value > 0 then
                number_input:set_text(tostring(value - 1))
            end
        end
    })

    local btn_number_plus = ui.button({
        x = 180, y = 600,
        w = 40, h = 30,
        text = "+",
        on_click = function()
            local value = tonumber(number_input:get_text()) or 0
            if value < 100 then
                number_input:set_text(tostring(value + 1))
            end
        end
    })

    page1:add(number_label)
    page1:add(number_input)
    page1:add(btn_number_minus)
    page1:add(btn_number_plus)

    -- ==================== 下拉框组件区域 ====================
    local combo_label = ui.label({
        x = 20, y = 650,
        text = "8. 下拉框组件演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local combo_box = ui.combo_box({
        x = 20, y = 680,
        w = 200, h = 30,
        options = { "选项1", "选项2", "选项3" },
        placeholder = "请选择",
        selected = 1,
        on_select = function(value, index, text)
            log.info("combo_box", "选择了:", text, "索引:", index)
        end
    })

    page1:add(combo_label)
    page1:add(combo_box)

    -- ==================== 图片轮播组件区域 ====================
    local picture_label = ui.label({
        x = 20, y = 730,
        text = "9. 图片自动轮播组件演示:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local pic = ui.picture({
        x = 20, y = 760,
        w = 128, h = 128,
        sources = { "/luadb/1.jpg", "/luadb/2.jpg", "/luadb/3.jpg" },
        autoplay = true,
        interval = 1500
    })

    local btn_picture_toggle = ui.button({
        x = 160, y = 760,
        w = 80, h = 30,
        text = "手动切换图片",
        on_click = function()
            pic:next()
        end
    })

    page1:add(picture_label)
    page1:add(pic)
    page1:add(btn_picture_toggle)

    -- 注册窗口到UI系统
    ui.add(page1)

end

sys.taskInit(ui_main)