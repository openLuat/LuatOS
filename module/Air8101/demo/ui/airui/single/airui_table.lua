--[[
@module table_page
@summary 表格组件演示
@version 1.0
@date 2026.01.27
@author 江访
@usage
本文件演示airui.table组件的用法，展示表格功能。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 创建3行3列的表格
    local tbl = airui.table({ 
        x = 10, 
        y = 10, 
        h = 200,
        w = 410,
        rows = 3, 
        cols = 3
    })
    
    -- 设置表格标题
    tbl:set_cell_text(0, 0, "姓名")
    tbl:set_cell_text(0, 1, "年龄")
    tbl:set_cell_text(0, 2, "城市")
    
    -- 设置表格内容
    tbl:set_cell_text(1, 0, "张三")
    tbl:set_cell_text(1, 1, "25")
    tbl:set_cell_text(1, 2, "北京")
    
    tbl:set_cell_text(2, 0, "李四")
    tbl:set_cell_text(2, 1, "30")
    tbl:set_cell_text(2, 2, "上海")

    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)