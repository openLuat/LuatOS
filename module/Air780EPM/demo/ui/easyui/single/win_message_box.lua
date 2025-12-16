--[[
@module  win_message_box
@summary 消息框组件演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为消息框组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加消息框组件显示通知信息；
3、启用自动换行功能显示长文本；
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

    -- 创建消息框组件
    local box = ui.message_box({ 
        x = 20, y = 20, 
        wordWrap = true,
        title = "Notification", 
        message = "May your journey be smooth and your future bright. Keep your passion and explore the world. May all your efforts be rewarded and you become the person you want to be. Good luck!"
    })
    
    -- 添加组件到窗口
    page1:add(box)

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