--[[
@module  win_button
@summary 基础按钮组件演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为基础按钮组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加基础按钮组件；
3、启动UI渲染循环持续刷新显示；

本文件的对外接口有1个：
1、返回主函数供main.lua调用；
]]

local function ui_main()
    sys.wait(500)

    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local page1 = ui.window({ background_color = ui.COLOR_WHITE })

    -- 创建按钮组件（文本模式）
    local btn1 = ui.button({ x = 20, y = 20, text = "基础按钮" })
    
    -- 添加组件到窗口
    page1:add(btn1)

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