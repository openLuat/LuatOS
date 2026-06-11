--[[
@module  win_dyn_progress_bar
@summary 动态进度条演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为动态进度条演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加进度条组件；
3、在主循环中动态更新进度条数值；
4、实现进度条往复动画效果；
5、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local direction = 1 
local current = 0

local function ui_main()

    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local page1 = ui.window({ background_color = ui.COLOR_WHITE })

    -- 创建进度条组件
    local pb = ui.progress_bar({ 
        x = 20, y = 20, 
        w = 280, h = 26
    })
    
    -- 添加组件到窗口
    page1:add(pb)

    -- 注册窗口到UI系统
    ui.add(page1)

    -- 启动exeasyui刷新主循环
    while true do
        -- 动态更新进度条数值
        current = current + direction
        if current >= 100 then
            direction = -1
        elseif current <= 0 then
            direction = 1
        end
        
        pb:set_progress(current)

        -- 等待30ms
        sys.wait(30)
    end
end

sys.taskInit(ui_main)