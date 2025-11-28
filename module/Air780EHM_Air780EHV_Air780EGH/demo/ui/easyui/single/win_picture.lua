--[[
@module  win_picture
@summary 静态图片显示演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为静态图片显示演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加静态图片显示组件；
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

    -- 创建静态图片组件
    local pic = ui.picture({ 
        x = 20, y = 20, 
        sources = {"/luadb/logo.jpg"}
    })
    
    -- 添加组件到窗口
    page1:add(pic)

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