--[[
@module  win_progress_bar
@summary 静态进度条演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为静态进度条演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加静态进度条组件；
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
    local progress_width = 600
    local progress_height = 30
    local progress_x = (page_w - progress_width) / 2
    local progress_y = 200

    -- 创建进度条组件
    local pb = ui.progress_bar({ 
        x = progress_x, y = progress_y, 
        w = progress_width, h = progress_height,
        progress = 50
    })
    
    -- 添加标题
    local title_label = ui.label({
        x = progress_x, y = progress_y - 60,
        text = "静态进度条演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加进度值标签
    local value_label = ui.label({
        x = progress_x, y = progress_y + 40,
        text = "当前进度: 50%",
        color = ui.COLOR_BLUE,
        size = 18
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(pb)
    page1:add(value_label)

    -- 注册窗口到UI系统
    ui.add(page1)

end

sys.taskInit(ui_main)