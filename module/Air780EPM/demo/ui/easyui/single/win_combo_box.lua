--[[
@module  win_combo_box
@summary 下拉框组件演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为下拉框组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加下拉框组件；
3、配置选项列表和选择回调；
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

    -- 创建下拉框组件
    local combo_box = ui.combo_box({
        x = 20, y = 20,
        w = 200, h = 30,
        options = { "Option 1", "Option 2", "Option 3" },
        placeholder = "Please select",
        selected = 1,
        on_select = function(value, index, text)
            log.info("component_page", "Selected:", text, "Index:", index)
        end
    })

    -- 添加组件到窗口
    page1:add(combo_box)

    -- 注册窗口到UI系统
    ui.add(page1)

end

sys.taskInit(ui_main)