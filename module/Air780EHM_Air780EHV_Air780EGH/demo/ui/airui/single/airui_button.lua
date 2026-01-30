--[[
@module button_page
@summary 按钮组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.button组件的用法，展示可点击按钮。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建按钮
    local btn = airui.button({ 
        x = 20, 
        y = 80, 
        on_click = function() 
            log.info("btn", "按钮被点击了") 
        end 
    })

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)