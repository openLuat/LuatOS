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
local current_font = nil

-- 创建UI
function label_page.create_ui()
    -- 创建主容器
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
    })

    -- 返回按钮
    local back_btn = airui.button({
        parent = title_bar,
        x = 250,
        y = 10,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function()
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

    -- 示例1: 基本文本标签
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本文本标签",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
    })

    local label1 = airui.label({
        parent = scroll_container,
        text = "这是一个文本标签",
        x = 20,
        y = 40,
        w = 280,
        h = 30
    })

    -- 示例2: 图标标签
    airui.label({
        parent = scroll_container,
        text = "示例2: 图标标签",
        x = 10,
        y = 80,
        w = 300,
        h = 20,
    })

    local icon_label = airui.label({
        parent = scroll_container,
        symbol = airui.AIRUI_SYMBOL_SETTINGS,
        x = 20,
        y = 115,
        w = 40,
        h = 40,
        on_click = function(self)
            log.info("label", "图标标签被点击")
        end
    })

    airui.label({
        parent = scroll_container,
        text = "点击图标",
        x = 70,
        y = 115,
        w = 100,
        h = 30,
    })

    -- 示例3: 动态更新文本
    airui.label({
        parent = scroll_container,
        text = "示例3: 动态更新文本",
        x = 10,
        y = 160,
        w = 300,
        h = 20,
    })

    local dynamic_label = airui.label({
        parent = scroll_container,
        text = "初始文本",
        x = 20,
        y = 190,
        w = 200,
        h = 30,
    })

    local update_btn = airui.button({
        parent = scroll_container,
        x = 230,
        y = 185,
        w = 70,
        h = 40,
        text = "更新",
        on_click = function()
            local current_time = os.date("%H:%M:%S")
            dynamic_label:set_text("时间: " .. current_time)
        end
    })

    -- 示例4: 多行文本
    airui.label({
        parent = scroll_container,
        text = "示例4: 多行文本",
        x = 10,
        y = 240,
        w = 300,
        h = 20,
    })

    local multiline_label = airui.label({
        parent = scroll_container,
        text = "这是一个多行文本标签，可以显示较长的文本内容。标签支持自动换行功能。",
        x = 20,
        y = 270,
        w = 280,
        h = 60,
    })

    -- 示例5: 不同字体大小
    airui.label({
        parent = scroll_container,
        text = "示例5: 不同字体大小和颜色:待更新接口",
        x = 10,
        y = 340,
        w = 300,
        h = 20,
    })


    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 点击标签可以触发事件",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
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