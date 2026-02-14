--[[
@module tabview_page
@summary 选项卡组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.tabview组件的用法，展示多页面切换功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建选项卡视图
    local tv = airui.tabview({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        tabs = { "页面A", "页面B", "页面C", "页面D", "页面E" }
    })

    -- 获取各个页面容器
    local page1 = tv:get_content(0)
    local page2 = tv:get_content(1)
    local page3 = tv:get_content(2)
    local page4 = tv:get_content(3)
    local page5 = tv:get_content(4)

    -- 在每个页面中添加标签
    airui.label({ parent = page1, text = "这是页面A", x = 100, y = 80 })
    airui.label({ parent = page2, text = "这是页面B", x = 100, y = 80 })
    airui.label({ parent = page3, text = "这是页面C", x = 100, y = 80 })
    airui.label({ parent = page4, text = "这是页面D", x = 100, y = 80 })
    airui.label({ parent = page5, text = "这是页面E", x = 100, y = 80 })

    -- 主循环,V1.0.3已不需要
    -- while true do
    --     airui.refresh()
    --     sys.wait(50)
    -- end
end

sys.taskInit(ui_main)