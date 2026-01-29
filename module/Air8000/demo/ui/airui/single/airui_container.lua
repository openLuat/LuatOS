--[[
@module container_page
@summary 容器组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.container组件的用法，展示如何创建容器并添加子组件。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建红色容器
    local box = airui.container({
        x = 100,
        y = 100,
        w = 100,
        h = 100,
        color = 0xff0000
    })

    -- 在容器中添加标签
    local label = airui.label({
        parent = box, -- 指定父容器
        text = "容器中的标签",
        x = 10,
        y = 50,
        w = 100,
        h = 100,
    })

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)