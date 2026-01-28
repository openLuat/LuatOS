--[[
@module hzfont_page
@summary HzFont矢量字体演示
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件演示HzFont矢量字体的各项特性，包括全字号无级缩放、抗锯齿优化和字体使用自由。
]]

local function ui_main()
    -- 初始化硬件
    lcd_drv.init()
    tp_drv.init()

    -- 加载hzfont字库
    airui.font_load({
        type = "hzfont",    -- 字体类型
        path = nil,         -- 使用内置字库
        size = 20,          -- 默认字体大小
        cache_size = 2048,  -- 缓存大小
        antialias = 4,      -- 抗锯齿等级
    })

    -- 创建主容器
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 800,
        h = 480,
        color = 0xFFFFFF,  -- 白色背景
    })

    -- 标题区域
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 800,
        h = 80,
        color = 0x2196F3,  -- 蓝色背景
    })

    local title_label = airui.label({
        parent = title_bar,
        text = "HzFont矢量字体演示",
        x = 10,
        y = 20,
        w = 300,
        h = 40,
    })

    -- 内容区域
    local content_area = airui.container({
        parent = main_container,
        x = 40,
        y = 100,
        w = 720,
        h = 340,
        color = 0xF8F9FA,  -- 浅灰色背景
        radius = 8,        -- 圆角
    })

    -- 第1行：全字号无级缩放 - 使用最大字号
    local line1_label = airui.label({
        parent = content_area,
        text = "全字号无级缩放：完整支持 12-255 字号，可随意指定任意大小，满足精细化的界面排版需求。",
        x = 20,
        y = 30,
        w = 680,
        h = 60,
    })
    
    -- 第2行：智能抗锯齿优化 - 使用中等字号和不同颜色
    local line2_label = airui.label({
        parent = content_area,
        text = "智能抗锯齿优化：支持可调节的抗锯齿等级，有效平滑字体边缘，提升显示细腻度与视觉效果。",
        x = 20,
        y = 110,
        w = 680,
        h = 50,
    })
    
    -- 第3行：字体使用高度自由 - 使用小字号和不同颜色
    local line3_label = airui.label({
        parent = content_area,
        text = "字体使用高度自由：既可使用固件内置字库快速上手，也能轻松加载外部 .ttf 字体文件，便于对定制字体与多国语言的支持。",
        x = 20,
        y = 180,
        w = 680,
        h = 80,
    })
    
    -- 主循环
    while true do
        airui.refresh()
        sys.wait(10)
    end
end

sys.taskInit(ui_main)