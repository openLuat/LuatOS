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

    -- 创建文本标签
    local label1 = airui.label({
        text = "Hello, World!",
        x = 20,
        y = 80,
        w = 100,
        h = 40,
    })

    -- 创建图标标签
    local label2 = airui.label({
        symbol = airui.SYMBOL_SETTINGS,
        x = 120,
        y = 80,
        w = 20,
        h = 20,
        on_click = function(self)
            log.info("label2", "设置图标被点击")
        end
    })
    -- 主循环,V1.0.3已不需要
    -- while true do
    --     airui.refresh()
    --     sys.wait(50)
    -- end
end

sys.taskInit(ui_main)