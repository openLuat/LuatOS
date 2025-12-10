--[[
@module  win_check_box
@summary 复选框组件演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为复选框组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加复选框组件；
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
    local checkbox_width = 200
    local checkbox_x = (page_w - checkbox_width) / 2

    -- 创建复选框组件
    local cb = ui.check_box({ 
        x = checkbox_x, y = 200, 
        w = 200, h = 30,
        text = "选择我",
        size = 18
    })
    
    -- 添加标题
    local title_label = ui.label({
        x = checkbox_x, y = 120,
        text = "复选框组件演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加说明标签
    local hint_label = ui.label({
        x = checkbox_x, y = 250,
        text = "点击复选框切换选中状态",
        color = ui.COLOR_GRAY,
        size = 14
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(cb)
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