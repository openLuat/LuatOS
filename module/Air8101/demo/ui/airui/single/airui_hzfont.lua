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

    -- 创建主容器（白色背景）
    local main_container = airui.container({
        x = 0,
        y = 0,
        w = 800,
        h = 480,
        color = 0xFFFFFF,
    })

    -- 标题栏（蓝色）
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 800,
        h = 80,
        color = 0x2196F3,
    })

    -- 标题：使用大字号 + 白色
    local title_label = airui.label({
        parent = title_bar,
        text = "HzFont 矢量字体演示 (Vector Font Demo)",
        x = 10,
        y = 20,
        w = 780,
        h = 40,
        font_size = 32, -- 大字号突出标题
        color = 0xFFFFFF, -- 白色文字
        align = airui.TEXT_ALIGN_CENTER
    })

    -- 内容区域（浅灰色圆角背景）
    local content_area = airui.container({
        parent = main_container,
        x = 40,
        y = 100,
        w = 720,
        h = 340,
        color = 0xF8F9FA,
        radius = 8,
    })

    -- 第1行：超大字号演示无级缩放（含英文、符号）
    local line1_label = airui.label({
        parent = content_area,
        text = "全字号无级缩放：字号 48 (Scale: 48px)",
        x = 20,
        y = 20,
        w = 680,
        h = 120,
        font_size = 48, -- 超大字号
        color = 0xE63946, -- 鲜艳红色
    })

    -- 第2行：中等字号 + 智能抗锯齿（多颜色）
    local line2_label = airui.label({
        parent = content_area,
        text = "智能抗锯齿优化：字号 28  Anti-aliasing  中文 English",
        x = 20,
        y = 150,
        w = 680,
        h = 70,
        font_size = 28, -- 中等字号
        color = 0x2A9D8F, -- 翠绿色
    })

    -- 第3行：小字号展示多语言和符号（长文本）
    local line3_label = airui.label({
        parent = content_area,
        text = "字体使用高度自由：内置字库 / 外部.ttf。支持中英符号",
        x = 20,
        y = 240,
        w = 680,
        h = 30,
        font_size = 24, -- 较小字号，适合多行文本
        color = 0x264653, -- 深蓝灰色
    })
end

sys.taskInit(ui_main)