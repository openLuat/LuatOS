--[[
@module hzfont_page
@summary HzFont矢量字体演示
@version 1.0.0
@date    2026.01.29
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
        size = 14,          -- 默认字体大小（竖屏适当减小）
        cache_size = 2048,  -- 缓存大小
        antialias = 1,      -- 抗锯齿等级
    })

    -- 创建主容器（竖屏尺寸）
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xFFFFFF,  -- 白色背景
    })

    -- 标题区域
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320, 
        h = 60, 
        color = 0x2196F3,  -- 蓝色背景
    })

    local title_label = airui.label({
        parent = title_bar,
        text = "HzFont矢量字体演示",
        x = 10,
        y = 15,
        w = 300,
        h = 30,
    })

    -- 创建可滚动内容区域
    local scroll_area = airui.container({
        parent = main_container,
        x = 0,
        y = 60,     -- 从标题栏下方开始
        w = 320,
        h = 400,    -- 留出底部空间
        color = 0xF8F9FA,  -- 浅灰色背景
    })

    -- 第1个特性卡片：全字号无级缩放
    local card1 = airui.container({
        parent = scroll_area,
        x = 10,
        y = 20,
        w = 300,
        h = 120,
        color = 0xFFFFFF,
        radius = 8,        -- 圆角
    })

    local card1_title = airui.label({
        parent = card1,
        text = "特性一：全字号无级缩放",
        x = 10,
        y = 10,
        w = 280,
        h = 25,
    })

    local card1_content = airui.label({
        parent = card1,
        text = "完整支持12-255字号，可随意指定任意大小，满足精细化界面排版需求。提供多种字号展示效果。",
        x = 10,
        y = 40,
        w = 280,
        h = 70,
    })

    -- 第2个特性卡片：智能抗锯齿优化
    local card2 = airui.container({
        parent = scroll_area,
        x = 10,
        y = 150,    -- 与上一个卡片保持间距
        w = 300,
        h = 120,
        color = 0xFFFFFF,
        radius = 8,
    })

    local card2_title = airui.label({
        parent = card2,
        text = "特性二：智能抗锯齿优化",
        x = 10,
        y = 10,
        w = 280,
        h = 25,
    })

    local card2_content = airui.label({
        parent = card2,
        text = "支持可调节的抗锯齿等级，有效平滑字体边缘，提升显示细腻度与视觉效果。适合不同尺寸文字渲染。",
        x = 10,
        y = 40,
        w = 280,
        h = 70,
    })

    -- 第3个特性卡片：字体使用高度自由
    local card3 = airui.container({
        parent = scroll_area,
        x = 10,
        y = 280,    -- 与上一个卡片保持间距
        w = 300,
        h = 120,
        color = 0xFFFFFF,
        radius = 8,
    })

    local card3_title = airui.label({
        parent = card3,
        text = "特性三：字体使用高度自由",
        x = 10,
        y = 10,
        w = 280,
        h = 25,
    })

    local card3_content = airui.label({
        parent = card3,
        text = "既可使用固件内置字库快速上手，也能轻松加载外部.ttf字体文件，便于对定制字体与多国语言的支持。",
        x = 10,
        y = 40,
        w = 280,
        h = 70,
    })

    -- 底部说明区域
    local bottom_info = airui.container({
        parent = main_container,
        x = 0,
        y = 460,    -- 放在底部
        w = 320,
        h = 20,
        color = 0x333333,
    })

    airui.label({
        parent = bottom_info,
        text = "HzFont矢量字体 v1.0",
        x = 10,
        y = 2,
        w = 300,
        h = 16,
    })
    
    -- 主循环
    while true do
        airui.refresh()
        sys.wait(50)
    end
end

sys.taskInit(ui_main)