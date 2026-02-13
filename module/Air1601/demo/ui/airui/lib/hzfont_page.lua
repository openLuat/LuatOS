--[[
@module     hzfont_page
@summary    矢量字体演示页面
@version    1.0.0
@date       2026.01.30
@author     江访
@usage      本文件是矢量字体的演示页面，展示中文字体的各种用法。
]]

local hzfont_page = {}

----------------------------------------------------------------
-- 页面UI元素
----------------------------------------------------------------
local main_container = nil
local current_font = nil

----------------------------------------------------------------
-- 辅助函数：创建带标题的容器
----------------------------------------------------------------
local function create_demo_container(parent, title, x, y, width, height)
    local container = airui.container({
        parent = parent,
        x = x,
        y = y,
        w = width,
        h = height,
        color = 0xFFFFFF,
        radius = 8,
    })

    airui.label({
        parent = container,
        text = title,
        x = 15,
        y = 10,
        w = width - 30,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    return container
end

----------------------------------------------------------------
-- 创建UI
----------------------------------------------------------------
function hzfont_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 1024,
        h = 600,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 1024,
        h = 60,
        color = 0x2196F3,
    })

    airui.label({
        parent = title_bar,
        text = "矢量字体演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
        color = 0xFFFFFF,
        size = 20,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 900,
        y = 15,
        w = 100,
        h = 35,
        text = "返回",
        size = 16,
        on_click = function()
            go_back()
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 70,
        w = 1024,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 使用两列网格布局
    local left_column_x = 20
    local right_column_x = 522
    local current_y = 10
    local container_width = 480
    local container_height = 120
    local container_gap_y = 15

    --------------------------------------------------------------------
    -- 示例1: 基本中文显示（左列）
    --------------------------------------------------------------------
    local demo1_container = create_demo_container(scroll_container, "示例1: 基本中文显示", left_column_x, current_y, container_width, container_height)

    airui.label({
        parent = demo1_container,
        text = "你好，世界！",
        x = 30,
        y = 50,
        w = 420,
        h = 50,
        color = 0x333333,
        size = 24,
    })

    -- 示例2: 长文本中文显示（右列）
    local demo2_container = create_demo_container(scroll_container, "示例2: 长文本中文", right_column_x, current_y, container_width, container_height)

    local long_text = "矢量字体支持高质量的中文显示，可以在不同分辨率下保持清晰，提供更好的视觉体验。"
    airui.label({
        parent = demo2_container,
        text = long_text,
        x = 30,
        y = 50,
        w = 420,
        h = 60,
        color = 0x333333,
        size = 16,
    })

    current_y = current_y + container_height + container_gap_y

    --------------------------------------------------------------------
    -- 示例3: 中英文混合（左列）
    --------------------------------------------------------------------
    local demo3_container = create_demo_container(scroll_container, "示例3: 中英文混合", left_column_x, current_y, container_width, container_height)

    airui.label({
        parent = demo3_container,
        text = "中文 Chinese 混合 Mixed 文本 Text 演示 Demo",
        x = 30,
        y = 50,
        w = 420,
        h = 50,
        color = 0x333333,
        size = 20,
    })

    -- 示例4: 常用汉字显示（右列）
    local demo4_container = create_demo_container(scroll_container, "示例4: 常用汉字", right_column_x, current_y, container_width, container_height)

    airui.label({
        parent = demo4_container,
        text = "天地玄黄 宇宙洪荒 日月盈昃 辰宿列张 寒来暑往 秋收冬藏",
        x = 30,
        y = 50,
        w = 420,
        h = 50,
        color = 0x333333,
        size = 18,
    })

    current_y = current_y + container_height + container_gap_y

    --------------------------------------------------------------------
    -- 示例5: 数字和标点（左列）
    --------------------------------------------------------------------
    local demo5_container = create_demo_container(scroll_container, "示例5: 数字标点", left_column_x, current_y, container_width, container_height)

    airui.label({
        parent = demo5_container,
        text = "数字: 1234567890 标点: ，。！？；：\"'（）【】《》",
        x = 30,
        y = 40,
        w = 420,
        h = 60,
        color = 0x333333,
        size = 16,
    })

    -- 示例6: 字体大小对比（右列）
    local demo6_container = create_demo_container(scroll_container, "示例6: 字体大小对比", right_column_x, current_y, container_width, container_height)

    -- 不同大小的字体示例
    airui.label({
        parent = demo6_container,
        text = "12px - 小号字体",
        x = 30,
        y = 40,
        w = 200,
        h = 30,
        color = 0x333333,
        size = 12,
    })

    airui.label({
        parent = demo6_container,
        text = "16px - 标准字体",
        x = 30,
        y = 70,
        w = 200,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    airui.label({
        parent = demo6_container,
        text = "24px - 大号字体",
        x = 250,
        y = 40,
        w = 200,
        h = 30,
        color = 0x333333,
        size = 24,
    })

    airui.label({
        parent = demo6_container,
        text = "32px - 特大字体",
        x = 250,
        y = 70,
        w = 200,
        h = 30,
        color = 0x333333,
        size = 32,
    })

    current_y = current_y + container_height + container_gap_y

    --------------------------------------------------------------------
    -- 示例7: 字体颜色对比（左列）
    --------------------------------------------------------------------
    local demo7_container = create_demo_container(scroll_container, "示例7: 字体颜色对比", left_column_x, current_y, container_width, container_height)

    -- 不同颜色的字体示例
    airui.label({
        parent = demo7_container,
        text = "红色字体",
        x = 30,
        y = 40,
        w = 200,
        h = 30,
        color = 0xFF0000,
        size = 18,
    })

    airui.label({
        parent = demo7_container,
        text = "绿色字体",
        x = 30,
        y = 75,
        w = 200,
        h = 30,
        color = 0x00FF00,
        size = 18,
    })

    airui.label({
        parent = demo7_container,
        text = "蓝色字体",
        x = 240,
        y = 40,
        w = 200,
        h = 30,
        color = 0x0000FF,
        size = 18,
    })

    airui.label({
        parent = demo7_container,
        text = "紫色字体",
        x = 240,
        y = 75,
        w = 200,
        h = 30,
        color = 0x800080,
        size = 18,
    })

    -- 示例8: 诗词展示（右列）
    local demo8_container = create_demo_container(scroll_container, "示例8: 诗词展示", right_column_x, current_y, container_width, container_height)

    airui.label({
        parent = demo8_container,
        text = "静夜思 - 李白",
        x = 30,
        y = 40,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 18,
    })

    airui.label({
        parent = demo8_container,
        text = "床前明月光，疑是地上霜。",
        x = 30,
        y = 70,
        w = 420,
        h = 25,
        color = 0x666666,
        size = 16,
    })

    airui.label({
        parent = demo8_container,
        text = "举头望明月，低头思故乡。",
        x = 30,
        y = 95,
        w = 420,
        h = 25,
        color = 0x666666,
        size = 16,
    })

    current_y = current_y + container_height + container_gap_y

    --------------------------------------------------------------------
    -- 示例9: 字体对齐演示（左列）
    --------------------------------------------------------------------
    local demo9_container = create_demo_container(scroll_container, "示例9: 字体对齐演示", left_column_x, current_y, container_width, container_height + 40)

    airui.label({
        parent = demo9_container,
        text = "左对齐文本",
        x = 30,
        y = 40,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    airui.label({
        parent = demo9_container,
        text = "居中对齐文本",
        x = 30,
        y = 80,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 16,
        align = "center",
    })

    airui.label({
        parent = demo9_container,
        text = "右对齐文本",
        x = 30,
        y = 120,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 16,
        align = "right",
    })

    -- 示例10: 特殊字符演示（右列）
    local demo10_container = create_demo_container(scroll_container, "示例10: 特殊字符", right_column_x, current_y, container_width, container_height + 40)

    airui.label({
        parent = demo10_container,
        text = "特殊字符和符号:",
        x = 30,
        y = 40,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    airui.label({
        parent = demo10_container,
        text = "① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩",
        x = 30,
        y = 75,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    airui.label({
        parent = demo10_container,
        text = "☆ ★ ○ ● △ ▲ □ ■ ◇ ◆",
        x = 30,
        y = 105,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    airui.label({
        parent = demo10_container,
        text = "← ↑ → ↓ ↔ ↕ ↖ ↗ ↘ ↙",
        x = 30,
        y = 135,
        w = 420,
        h = 30,
        color = 0x333333,
        size = 16,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 矢量字体支持高质量中文显示，支持多种大小、颜色和对齐方式",
        x = 20,
        y = 560,
        w = 600,
        h = 25,
        color = 0x666666,
        size = 14,
    })
end

----------------------------------------------------------------
-- 初始化页面
----------------------------------------------------------------
function hzfont_page.init(params)
    hzfont_page.create_ui()
end

----------------------------------------------------------------
-- 清理页面
----------------------------------------------------------------
function hzfont_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    current_font = nil
end

return hzfont_page