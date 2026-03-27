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


    -- 主容器（白色背景）
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xFFFFFF,
    })

    -- 标题栏（蓝色）高度适当缩小
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 60,
        color = 0x2196F3,
    })

    -- 标题：字号缩小，保证完整显示
    local title_label = airui.label({
        parent = title_bar,
        text = "HzFont 演示",
        x = 10,
        y = 15,
        w = 310,
        h = 30,
        font_size = 24, -- 适应小屏
        color = 0xFFFFFF,
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域（边距缩小）
    local content_area = airui.container({
        parent = main_container,
        x = 10,
        y = 70,
        w = 300,
        h = 400,
        color = 0xF8F9FA,
        radius = 6,
    })

    -- 第1行：大字号，但适当减小
    local line1_label = airui.label({
        parent = content_area,
        text = "无级缩放 36px",
        x = 10,
        y = 15,
        w = 280,
        h = 72,
        font_size = 36,
        color = 0xE63946,
    })

    -- 第2行：中等字号
    local line2_label = airui.label({
        parent = content_area,
        text = "抗锯齿 24pt 中 / English",
        x = 10,
        y = 95,
        w = 280,
        h = 60,
        font_size = 24,
        color = 0x2A9D8F,
    })

    -- 第3行：小字号 + 符号（文本折行）
    local line3_label = airui.label({
        parent = content_area,
        text = "支持外部字库加载其他文字",
        x = 10,
        y = 200,
        w = 280,
        h = 130,
        font_size = 20,
        color = 0x264653,
    })

    -- 可增加额外示例行以填充空间（可选）
    local line4_label = airui.label({
        parent = content_area,
        text = "字号 18 - 小字清晰显示",
        x = 10,
        y = 270,
        w = 280,
        h = 30,
        font_size = 18,
        color = 0x6C757D,
    })
end

sys.taskInit(ui_main)