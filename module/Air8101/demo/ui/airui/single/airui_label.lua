--[[
@module label_page
@summary 标签组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.label组件的用法，展示文本标签功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建标签
    local label = airui.label({
        text = "Hello, World!",
        x = 20,
        y = 80,
        w = 200,
        h = 40,
    })

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)