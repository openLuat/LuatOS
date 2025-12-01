--[[
@module  win_label
@summary 基础标签组件演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为基础标签组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加静态标签组件显示"hello exEasyUI"文本；
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

    -- 创建标签组件
    local lbl = ui.label({ x = 20, y = 20, text = "hello exEasyUI"})

    -- 添加组件到窗口
    page1:add(lbl)

    -- 注册窗口到UI系统
    ui.add(page1)

    -- 启动exeasyui刷新主循环
    while true do
        -- 更新时间给文本组件lbl
        lbl:set_text("时间:"..os.date("%Y-%m-%d %H:%M:%S"))
        -- 刷新显示
        ui.refresh()
        -- 等待30ms
        sys.wait(30)
    end

end

sys.taskInit(ui_main)