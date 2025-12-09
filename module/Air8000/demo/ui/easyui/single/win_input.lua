--[[
@module  win_input
@summary 文本输入框演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为文本输入框演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加文本输入框组件；
3、设置占位符文本和最大长度限制；
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

    -- 创建文本输入框组件
    local text_input = ui.input({
        x = 20, y = 20,
        w = 200, h = 30,
        placeholder = "请输入文本...",
        max_length = 20
    })

    -- 添加组件到窗口
    page1:add(text_input)

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