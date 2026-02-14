--[[
@module  label_page
@summary 标签组件演示页面
@version 1.0.0
@date    2026.01.30
@author  江访
@usage
本文件是标签组件的演示页面，展示标签的各种用法。
]]

local label_page = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function label_page.create_ui()
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
        color = 0x4CAF50,
    })

    airui.label({
        parent = title_bar,
        text = "标签组件演示",
        x = 20,
        y = 15,
        w = 300,
        h = 30,
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

    -- 使用两列布局
    local left_column_x = 20
    local right_column_x = 522
    local y_offset = 10
    local section_height = 100

    -- 示例1: 基本文本标签（左列）
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本文本标签",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local label1 = airui.label({
        parent = scroll_container,
        text = "这是一个基本的文本标签",
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 300,
        h = 40,
        size = 18,
    })

    -- 示例2: 图标标签（右列）
    airui.label({
        parent = scroll_container,
        text = "示例2: 图标标签",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local icon_label = airui.label({
        parent = scroll_container,
        symbol = airui.SYMBOL_SETTINGS,
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 50,
        h = 50,
        size = 30,
        on_click = function(self)
            log.info("label", "图标标签被点击")
        end
    })

    airui.label({
        parent = scroll_container,
        text = "点击图标（此图标可点击）",
        x = right_column_x + 90,
        y = y_offset + 50,
        w = 200,
        h = 30,
        size = 16,
    })

    y_offset = y_offset + section_height

    -- 示例3: 动态更新文本（左列）
    airui.label({
        parent = scroll_container,
        text = "示例3: 动态更新文本",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local dynamic_label = airui.label({
        parent = scroll_container,
        text = "初始文本内容",
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 300,
        h = 40,
        size = 18,
    })

    local update_btn = airui.button({
        parent = scroll_container,
        x = left_column_x + 340,
        y = y_offset + 35,
        w = 120,
        h = 50,
        text = "更新时间",
        size = 16,
        on_click = function()
            local current_time = os.date("%H:%M:%S")
            dynamic_label:set_text("当前时间: " .. current_time)
        end
    })

    -- 示例4: 多行文本（右列）
    airui.label({
        parent = scroll_container,
        text = "示例4: 多行文本标签",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local multiline_label = airui.label({
        parent = scroll_container,
        text = "这是一个多行文本标签，可以显示较长的文本内容。标签支持自动换行功能。多行文本非常适合展示说明性内容或较长的描述信息。",
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 400,
        h = 120,
        size = 16,
    })

    y_offset = y_offset + 150

    -- 示例5: 不同字体大小（左列）
    airui.label({
        parent = scroll_container,
        text = "示例5: 不同字体大小",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    airui.label({
        parent = scroll_container,
        text = "12号字体 - 小号文字",
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 300,
        h = 30,
        size = 12,
    })

    airui.label({
        parent = scroll_container,
        text = "16号字体 - 标准文字",
        x = left_column_x + 20,
        y = y_offset + 75,
        w = 300,
        h = 30,
        size = 16,
    })

    airui.label({
        parent = scroll_container,
        text = "20号字体 - 大号文字",
        x = left_column_x + 20,
        y = y_offset + 110,
        w = 300,
        h = 30,
        size = 20,
    })

    airui.label({
        parent = scroll_container,
        text = "24号字体 - 标题文字",
        x = left_column_x + 20,
        y = y_offset + 145,
        w = 300,
        h = 30,
        size = 24,
    })

    -- 示例6: 不同字体颜色（右列）
    airui.label({
        parent = scroll_container,
        text = "示例6: 不同字体颜色",
        x = right_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    airui.label({
        parent = scroll_container,
        text = "红色文字",
        x = right_column_x + 20,
        y = y_offset + 40,
        w = 200,
        h = 30,
        color = 0xFF0000,
        size = 16,
    })

    airui.label({
        parent = scroll_container,
        text = "绿色文字",
        x = right_column_x + 20,
        y = y_offset + 75,
        w = 200,
        h = 30,
        color = 0x00FF00,
        size = 16,
    })

    airui.label({
        parent = scroll_container,
        text = "蓝色文字",
        x = right_column_x + 20,
        y = y_offset + 110,
        w = 200,
        h = 30,
        color = 0x0000FF,
        size = 16,
    })

    airui.label({
        parent = scroll_container,
        text = "紫色文字",
        x = right_column_x + 20,
        y = y_offset + 145,
        w = 200,
        h = 30,
        color = 0x800080,
        size = 16,
    })

    y_offset = y_offset + 180

    -- 示例7: 带背景的标签（左列）
    airui.label({
        parent = scroll_container,
        text = "示例7: 带背景的标签",
        x = left_column_x,
        y = y_offset,
        w = 400,
        h = 30,
        size = 18,
    })

    local bg_container1 = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 40,
        w = 350,
        h = 50,
        color = 0xE3F2FD,
        radius = 10,
    })

    airui.label({
        parent = bg_container1,
        text = "蓝色背景的标签",
        x = 20,
        y = 15,
        w = 310,
        h = 20,
        size = 16,
    })

    local bg_container2 = airui.container({
        parent = scroll_container,
        x = left_column_x + 20,
        y = y_offset + 100,
        w = 350,
        h = 50,
        color = 0xFFEBEE,
        radius = 10,
    })

    airui.label({
        parent = bg_container2,
        text = "红色背景的标签",
        x = 20,
        y = 15,
        w = 310,
        h = 20,
        color = 0xD32F2F,
        size = 16,
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 标签支持文本、图标、多行显示和动态更新",
        x = 20,
        y = 560,
        w = 500,
        h = 25,
        size = 14,
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