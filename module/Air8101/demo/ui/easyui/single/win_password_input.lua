--[[
@module  win_password_input
@summary 密码输入框演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为密码输入框演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加密码输入框组件；
3、添加显示/隐藏密码切换按钮；
4、实现密码可见性切换功能；
5、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local function ui_main()

    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local page1 = ui.window({ background_color = ui.COLOR_WHITE })

    -- 计算居中位置
    local page_w, page_h = lcd.getSize()
    local container_width = 400
    local container_x = (page_w - container_width) / 2

    -- 创建密码输入框组件
    local password_input = ui.input({
        x = container_x, y = 150,
        w = 250, h = 40,
        placeholder = "请输入密码...",
        input_type = "password",
        max_length = 16,
        size = 16
    })

    -- 创建密码显示/隐藏切换按钮
    local password_visible = false
    local btn_password_toggle = ui.button({
        x = container_x + 260, y = 150,
        w = 100, h = 40,
        text = "显示密码",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        size = 16,
        on_click = function()
            password_visible = not password_visible
            password_input.input_type = password_visible and "text" or "password"
            btn_password_toggle:set_text(password_visible and "隐藏密码" or "显示密码")
        end
    })

    -- 添加标题
    local title_label = ui.label({
        x = container_x, y = 80,
        text = "密码输入框演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加提示标签
    local hint_label = ui.label({
        x = container_x, y = 210,
        text = "点击右侧按钮切换密码可见性",
        color = ui.COLOR_GRAY,
        size = 14
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(password_input)
    page1:add(btn_password_toggle)
    page1:add(hint_label)

    -- 注册窗口到UI系统
    ui.add(page1)

    -- 启动exeasyui刷新主循环
    while true do
        -- 刷新显示
        ui.refresh()
        -- 等待30ms
        sys.wait(30)
    end
end

sys.taskInit(ui_main)