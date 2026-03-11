--[[
@module  label_page
@summary 标签组件演示页面
@version 1.0
@date    2026.02.05
@author  江访
@usage
本文件是标签组件的演示页面，展示标签的各种用法。
]]

local label_page = {}

-- 页面UI元素
local main_container = nil
local current_font = nil

-- 创建UI
function label_page.create_ui()
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
        color = 0x4CAF50,
    })

    airui.label({
        parent = title_bar,
        text = "标签组件演示",
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
            go_back()
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

    -- 示例1: 基本文本标签
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本文本标签",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local label1 = airui.label({
        parent = scroll_container,
        text = "这是一个文本标签",
        x = 20,
        y = current_y,
        w = 280,
        h = 30,
        font_size = 14,
    })
    current_y = current_y + 40

    -- 示例2: 图标标签（使用符号）
    airui.label({
        parent = scroll_container,
        text = "示例2: 图标标签",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local icon_label = airui.label({
        parent = scroll_container,
        symbol = airui.SYMBOL_SETTINGS,                     -- 使用符号字符串
        x = 20,
        y = current_y,
        w = 40,
        h = 40,
        font_size = 24,
        on_click = function(self)
            log.info("label", "图标标签被点击")
        end
    })

    airui.label({
        parent = scroll_container,
        text = "点击图标",
        x = 70,
        y = current_y + 5,
        w = 100,
        h = 30,
        font_size = 14,
    })
    current_y = current_y + 50

    -- 示例3: 动态更新文本
    airui.label({
        parent = scroll_container,
        text = "示例3: 动态更新文本",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local dynamic_label = airui.label({
        parent = scroll_container,
        text = "初始文本",
        x = 20,
        y = current_y,
        w = 200,
        h = 30,
        font_size = 14,
    })

    local update_btn = airui.button({
        parent = scroll_container,
        x = 230,
        y = current_y - 5,
        w = 70,
        h = 40,
        text = "更新",
        on_click = function(self)
            local current_time = os.date("%H:%M:%S")
            dynamic_label:set_text("时间: " .. current_time)
        end
    })
    current_y = current_y + 50

    -- 示例4: 多行文本
    airui.label({
        parent = scroll_container,
        text = "示例4: 多行文本",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local multiline_label = airui.label({
        parent = scroll_container,
        text = "这是一个多行文本标签，可以显示较长的文本内容。标签支持自动换行功能。",
        x = 20,
        y = current_y,
        w = 280,
        h = 60,
        font_size = 14,
    })
    current_y = current_y + 70

    -- 示例5: 不同字体大小和颜色
    airui.label({
        parent = scroll_container,
        text = "示例5: 不同字体大小和颜色",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local size_label1 = airui.label({
        parent = scroll_container,
        text = "12px 红色",
        x = 20,
        y = current_y,
        w = 100,
        h = 30,
        font_size = 12,
        color = 0xFF0000,
    })

    local size_label2 = airui.label({
        parent = scroll_container,
        text = "16px 绿色",
        x = 130,
        y = current_y,
        w = 100,
        h = 30,
        font_size = 16,
        color = 0x00FF00,
    })

    local size_label3 = airui.label({
        parent = scroll_container,
        text = "20px 蓝色",
        x = 240,
        y = current_y,
        w = 60,
        h = 50,
        font_size = 20,
        color = 0x0000FF,
    })
    current_y = current_y + 60

    -- 示例6: 对齐方式 (V1.1.0 新增)
    airui.label({
        parent = scroll_container,
        text = "示例6: 对齐方式",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    local align_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = current_y,
        w = 280,
        h = 120,
        color = 0xEEEEEE,
        radius = 8,
    })
    current_y = current_y + 130

    airui.label({
        parent = align_container,
        text = "左对齐",
        x = 10,
        y = 10,
        w = 80,
        h = 30,
        font_size = 14,
        align = airui.TEXT_ALIGN_LEFT,   -- 默认左对齐
    })

    airui.label({
        parent = align_container,
        text = "居中对齐",
        x = 100,
        y = 10,
        w = 80,
        h = 30,
        font_size = 14,
        align = airui.TEXT_ALIGN_CENTER, -- 居中
    })

    airui.label({
        parent = align_container,
        text = "右对齐",
        x = 190,
        y = 10,
        w = 80,
        h = 30,
        font_size = 14,
        align = airui.TEXT_ALIGN_RIGHT,  -- 右对齐
    })

    -- 示例7: 自定义字体句柄 (V1.1.0 新增)
    airui.label({
        parent = scroll_container,
        text = "示例7: 自定义字体",
        x = 10,
        y = current_y,
        w = 300,
        h = 20,
        font_size = 14,
    })
    current_y = current_y + 25

    -- 加载外置字体（假设有字体文件）
    local font_hz = airui.font_load({
        type = "hzfont",
        path = "/luadb/msyh.ttf",  -- 需实际存在
        size = 20,
    })

    if font_hz then
        airui.label({
            parent = scroll_container,
            text = "使用外置字体: 微软雅黑",
            x = 20,
            y = current_y,
            w = 280,
            h = 30,
            font = font_hz,
            font_size = 20,
            color = 0x333333,
        })
        current_y = current_y + 40
    else
        airui.label({
            parent = scroll_container,
            text = "外置字体加载失败，使用默认字体",
            x = 20,
            y = current_y,
            w = 280,
            h = 30,
            color = 0x999999,
        })
        current_y = current_y + 40
    end

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 点击标签可以触发事件",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        font_size = 14,
    })
end

-- 初始化页面
function label_page.init(params)
    label_page.create_ui()
end

-- 清理页面
function label_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return label_page