--[[
@module win_page
@summary 窗口组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.win组件的用法，展示窗口功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建窗口
    local win1 = airui.win({
        title = "示例窗口",
        x = 0,
        y = 0,
        w = 320,
        h = 400,
        close_btn = true,
        auto_center = false,
        style = "radius",
        on_close = function(self)
            log.info("win", "窗口已关闭")
        end
    })

    -- 在窗口中添加标签
    local label1 = airui.label({
        parent = win1,
        text = "窗口中的内容",
        x = 20,
        y = 20,
    })

    -- 当前版本子组件还需再添加进win组件，后续版本可能添加为父级即可
    win1:add_content(label1)

    -- 主循环,V1.0.3已不需要
    -- while true do
    --     airui.refresh()
    --     sys.wait(50)
    -- end
end

sys.taskInit(ui_main)