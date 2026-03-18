--[[
@module     hzfont_win
@summary    矢量字体演示窗口（exwin窗口管理版本）
@version    1.1.0
@date       2026.03.17
@author     江访
@usage      本文件是矢量字体的演示窗口，采用exwin窗口管理扩展库。
            展示中文字体的各种用法，通过消息机制打开和关闭。
]]

-- 窗口ID
local win_id = nil

-- 窗口UI元素
local main_container = nil
local current_font = nil


-- 辅助函数：创建带标题的容器

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
        x = 10,
        y = 5,
        w = width - 20,
        h = 25,
        color = 0x333333,
        font_size = 14,
    })

    return container
end


-- 创建UI
local function create_ui()
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xF5F5F5,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0x2196F3,
    })

    airui.label({
        parent = title_bar,
        text = "矢量字体演示",
        x = 10,
        y = 15,
        w = 200,
        h = 20,
        font_size = 16,
        color = 0xFFFFFF,
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function(self)
            exwin.close(win_id)
        end
    })

    -- 滚动容器
    local scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 370,
        color = 0xF5F5F5,
    })

    local current_y = 10

    ----
    -- 示例1: 基本中文显示
    ----
    local demo1_container = create_demo_container(scroll_container, "示例1: 基本中文显示", 10, current_y, 300, 80)
    current_y = current_y + 80 + 10

    airui.label({
        parent = demo1_container,
        text = "你好，世界！",
        x = 20,
        y = 30,
        w = 260,
        h = 40,
        color = 0x333333,
        font_size = 18,
    })

    ----
    -- 示例2: 长文本中文显示
    ----
    local demo2_container = create_demo_container(scroll_container, "示例2: 长文本中文", 10, current_y, 300, 100)
    current_y = current_y + 100 + 10

    local long_text = "矢量字体支持高质量的中文显示，可以在不同分辨率下保持清晰，提供更好的视觉体验。"
    airui.label({
        parent = demo2_container,
        text = long_text,
        x = 20,
        y = 30,
        w = 260,
        h = 60,
        color = 0x333333,
        font_size = 14,
    })

    ----
    -- 示例3: 中英文混合
    ----
    local demo3_container = create_demo_container(scroll_container, "示例3: 中英文混合", 10, current_y, 300, 80)
    current_y = current_y + 80 + 10

    airui.label({
        parent = demo3_container,
        text = "中文 Chinese 混合 Mixed 文本 Text",
        x = 20,
        y = 30,
        w = 260,
        h = 40,
        color = 0x333333,
        font_size = 16,
    })

    ----
    -- 示例4: 常用汉字显示
    ----
    local demo4_container = create_demo_container(scroll_container, "示例4: 常用汉字", 10, current_y, 300, 80)
    current_y = current_y + 80 + 10

    airui.label({
        parent = demo4_container,
        text = "天地玄黄 宇宙洪荒 日月盈昃 辰宿列张",
        x = 20,
        y = 30,
        w = 260,
        h = 40,
        color = 0x333333,
        font_size = 16,
    })

    ----
    -- 示例5: 数字和标点
    ----
    local demo5_container = create_demo_container(scroll_container, "示例5: 数字标点", 10, current_y, 300, 100)
    current_y = current_y + 100 + 10

    airui.label({
        parent = demo5_container,
        text = "数字: 1234567890\n标点: ，。！？；：\"'（）【】《》",
        x = 20,
        y = 30,
        w = 260,
        h = 60,
        color = 0x333333,
        font_size = 14,
    })

    ----
    -- 示例6: 字体大小对比
    ----
    local demo7_container = create_demo_container(scroll_container, "示例6: 字体大小对比", 10, current_y, 300, 120)
    current_y = current_y + 120 + 10

    airui.label({
        parent = demo7_container,
        text = "12px - 小号字体",
        x = 20,
        y = 30,
        w = 260,
        h = 30,
        color = 0x333333,
        font_size = 12,
    })

    airui.label({
        parent = demo7_container,
        text = "16px - 中号字体",
        x = 20,
        y = 55,
        w = 260,
        h = 30,
        color = 0x333333,
        font_size = 16,
    })

    airui.label({
        parent = demo7_container,
        text = "20px - 大号字体",
        x = 20,
        y = 80,
        w = 260,
        h = 30,
        color = 0x333333,
        font_size = 20,
    })

    ----
    -- 示例7: 字体颜色对比
    ----
    local demo8_container = create_demo_container(scroll_container, "示例7: 字体颜色对比", 10, current_y, 300, 100)

    airui.label({
        parent = demo8_container,
        text = "红色字体",
        x = 20,
        y = 30,
        w = 260,
        h = 30,
        color = 0xFF0000,
        font_size = 16,
    })

    airui.label({
        parent = demo8_container,
        text = "绿色字体",
        x = 20,
        y = 55,
        w = 260,
        h = 30,
        color = 0x00FF00,
        font_size = 16,
    })

    airui.label({
        parent = demo8_container,
        text = "蓝色字体",
        x = 20,
        y = 80,
        w = 260,
        h = 30,
        color = 0x0000FF,
        font_size = 16,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 矢量字体支持高质量中文显示",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        color = 0x666666,
        font_size = 12,
    })
end

-- 窗口创建回调
local function on_create()
    create_ui()
end

-- 窗口销毁回调
local function on_destroy()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
    current_font = nil
    win_id = nil
    log.info("hzfont_win", "窗口销毁")
end

-- 窗口获得焦点回调
local function on_get_focus()
    log.info("hzfont_win", "窗口获得焦点")
end

-- 窗口失去焦点回调
local function on_lose_focus()
    log.info("hzfont_win", "窗口失去焦点")
end

-- 订阅打开矢量字体窗口消息
sys.subscribe("OPEN_HZFONT_WIN", function()
    if not exwin.is_active(win_id) then
        win_id = exwin.open({
            on_create = on_create,
            on_destroy = on_destroy,
            on_get_focus = on_get_focus,
            on_lose_focus = on_lose_focus,
        })
        log.info("hzfont_win", "窗口打开，ID:", win_id)
    end
end)