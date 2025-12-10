--[[
@module  win_toggle_button
@summary 切换按钮演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为切换按钮演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加图标模式切换按钮组件；
3、实现按钮点击切换图片功能；
4、启动UI渲染循环持续刷新显示；

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
    local button_size = 120
    local button_x = (page_w - button_size) / 2
    local button_y = (page_h - button_size) / 2

    -- 创建切换按钮组件（图标模式）
    local btn2 = ui.button({
        x = button_x, y = button_y, 
        w = button_size, h = button_size,
        toggle = true,                  -- 启用切换模式
        src = "/luadb/4.jpg",           -- 默认图片
        src_toggled = "/luadb/5.jpg",   -- 切换状态时的图片
    })
    
    -- 添加标题
    local title_label = ui.label({
        x = button_x, y = button_y - 80,
        text = "切换按钮演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加说明标签
    local hint_label = ui.label({
        x = button_x, y = button_y + button_size + 20,
        text = "点击按钮切换图片",
        color = ui.COLOR_GRAY,
        size = 16
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(btn2)
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