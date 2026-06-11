--[[
@module  win_button
@summary 基础按钮组件演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为基础按钮组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加基础按钮组件；
3、启动UI渲染循环持续刷新显示；

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
    local button_width = 200
    local button_height = 50
    local button_x = (page_w - button_width) / 2
    local button_y = (page_h - button_height) / 2

    -- 创建按钮组件（文本模式）
    local btn1 = ui.button({ 
        x = button_x, y = button_y, 
        w = button_width, h = button_height,
        text = "基础按钮",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        size = 18
    })
    
    -- 添加说明标签
    local title_label = ui.label({
        x = button_x, y = button_y - 60,
        text = "基础按钮演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(btn1)

    -- 注册窗口到UI系统
    ui.add(page1)

end

sys.taskInit(ui_main)