--[[
@module  hzfont_page
@summary HzFont矢量字体演示
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件演示如何使用HzFont矢量字体支持中文显示。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 加载HzFont字库
    airui.font_load({
        type = "hzfont",    -- 字体类型
        path = nil,         -- 使用内置字库
        size = 50,          -- 字体大小
        cache_size = 2048,  -- 缓存大小
        antialias = 1,      -- 抗锯齿等级
    })
    
    -- 创建中文标签
    local label = airui.label({
        text = "中文字体演示",
        x = 50,
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