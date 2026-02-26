--[[
@module  button_page
@summary 按钮组件演示页面
@version 1.0
@date    2026.02.05
@author  江访
@usage
本文件是按钮组件的演示页面，展示按钮的各种用法。
]]

local button_page = {}

-- 页面UI元素
local main_container = nil

-- 创建UI
function button_page.create_ui()
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
        color = 0xF44336,
    })

    airui.label({
        parent = title_bar,
        text = "按钮组件演示",
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

    -- 示例1: 基本按钮
    airui.label({
        parent = scroll_container,
        text = "示例1: 基本按钮",
        x = 10,
        y = 10,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local basic_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 40,
        w = 120,
        h = 40,
        text = "点击我",
        on_click = function(self)
            log.info("button", "基本按钮被点击")
        end
    })

    -- 示例2: 不同大小的按钮
    airui.label({
        parent = scroll_container,
        text = "示例2: 不同大小的按钮",
        x = 10,
        y = 100,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local small_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 130,
        w = 80,
        h = 30,
        text = "小按钮",
        on_click = function(self)
            log.info("button", "小按钮被点击")
        end
    })

    local large_btn = airui.button({
        parent = scroll_container,
        x = 120,
        y = 125,
        w = 180,
        h = 40,
        text = "大按钮",
        on_click = function(self)
            log.info("button", "大按钮被点击")
        end
    })

    -- 示例3: 动态更新文本
    local dynamic_label = airui.label({
        parent = scroll_container,
        text = "示例3: 动态更新文本",
        x = 10,
        y = 190,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local click_count = 0
    local dynamic_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 220,
        w = 140,
        h = 40,
        text = "点击计数: 0",
        on_click = function(self)
            click_count = click_count + 1
            self:set_text("点击计数: " .. click_count)   -- v1.0.3 使用 self
            dynamic_label:set_text("示例3: 动态更新文本")
        end
    })

    -- 示例4: 按钮组
    airui.label({
        parent = scroll_container,
        text = "示例4: 按钮组",
        x = 10,
        y = 280,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local btn_container = airui.container({
        parent = scroll_container,
        x = 20,
        y = 310,
        w = 280,
        h = 60,
        color = 0xE0E0E0,
        radius = 5,
    })

    local btn1 = airui.button({
        parent = btn_container,
        x = 10,
        y = 10,
        w = 80,
        h = 40,
        text = "选项1",
        on_click = function(self)
            log.info("button", "选项1被选中")
        end
    })

    local btn2 = airui.button({
        parent = btn_container,
        x = 100,
        y = 10,
        w = 80,
        h = 40,
        text = "选项2",
        on_click = function(self)
            log.info("button", "选项2被选中")
        end
    })

    local btn3 = airui.button({
        parent = btn_container,
        x = 190,
        y = 10,
        w = 80,
        h = 40,
        text = "选项3",
        on_click = function(self)
            log.info("button", "选项3被选中")
        end
    })

    -- 示例5: 销毁按钮
    airui.label({
        parent = scroll_container,
        text = "示例5: 销毁按钮",
        x = 10,
        y = 390,
        w = 300,
        h = 20,
        font_size = 14,
    })

    local toggle_btn = airui.button({
        parent = scroll_container,
        x = 20,
        y = 420,
        w = 120,
        h = 40,
        text = "可点击",
        on_click = function(self)
            log.info("button", "按钮被点击")
        end
    })

    local disable_btn = airui.button({
        parent = scroll_container,
        x = 160,
        y = 420,
        w = 120,
        h = 40,
        text = "销毁可点击",
        on_click = function(self)
            toggle_btn:destroy()
            log.info("button", "已销毁可点击按钮")
        end
    })

    -- 底部信息
    airui.label({
        parent = main_container,
        text = "提示: 按钮支持点击事件和动态更新",
        x = 10,
        y = 440,
        w = 300,
        h = 20,
        font_size = 14,
    })
end

-- 初始化页面
function button_page.init(params)
    button_page.create_ui()
end

-- 清理页面
function button_page.cleanup()
    if main_container then
        main_container:destroy()
        main_container = nil
    end
end

return button_page