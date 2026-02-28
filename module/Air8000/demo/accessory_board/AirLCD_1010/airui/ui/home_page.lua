--[[
@module  home_page
@summary AirUI演示系统主页
@version 1.0
@date    2026.02.05
@author  江访
@usage
本文件是AirUI演示系统的主页，提供所有功能演示的入口。
]]

local home_page = {}

-- 页面UI元素
local main_container = nil
local scroll_container = nil

-- 演示模块列表
local demos = {
    -- AirUI组件演示
    {name = "所有组件演示", icon = airui.SYMBOL_OK, page = "all_component", color = 0x007AFF},
    {name = "标签组件", icon = airui.SYMBOL_REFRESH, page = "label", color = 0x4CAF50},
    {name = "按钮组件", icon = airui.SYMBOL_LOOP, page = "button", color = 0xF44336},
    {name = "容器组件", icon = airui.SYMBOL_SD_CARD, page = "container", color = 0xFF9800},
    {name = "进度条组件", icon = airui.SYMBOL_SHUFFLE, page = "bar", color = 0x9C27B0},
    {name = "开关组件", icon = airui.SYMBOL_COPY, page = "switch", color = 0x00BCD4},
    {name = "下拉框组件", icon = airui.SYMBOL_DOWN, page = "dropdown", color = 0x795548},
    {name = "表格组件", icon = airui.SYMBOL_LIST, page = "table", color = 0x607D8B},
    {name = "输入框组件", icon = airui.SYMBOL_EDIT, page = "input", color = 0x3F51B5},
    {name = "消息框组件", icon = airui.SYMBOL_CALL, page = "msgbox", color = 0xE91E63},
    {name = "图片组件", icon = airui.SYMBOL_IMAGE, page = "image", color = 0x8BC34A},
    {name = "选项卡组件", icon = airui.SYMBOL_PASTE, page = "tabview", color = 0xFF5722},
    {name = "窗口组件", icon = airui.SYMBOL_BELL, page = "win", color = 0x009688},
    {name = "页面切换演示", icon = airui.SYMBOL_LEFT, page = "switch_page_demo", color = 0x673AB7},
    {name = "矢量字体演示", icon = airui.SYMBOL_EYE_OPEN, page = "hzfont", color = 0x2196F3},
    {name = "俄罗斯方块游戏", icon = airui.SYMBOL_WARNING, page = "game", color = 0xFF4081},
}

-- 创建主页UI
function home_page.create_ui()
    -- 创建主容器
    main_container = airui.container({
        x = 0,
        y = 0,
        w = 320,
        h = 480,
        color = 0xF8F9FA,
    })

    -- 标题栏
    local title_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 0,
        w = 320,
        h = 50,
        color = 0x007AFF,
    })

    airui.label({
        parent = title_bar,
        text = "AirUI演示系统",
        x = 10,
        y = 20,
        w = 300,
        h = 30,
    })

    -- 滚动容器
    scroll_container = airui.container({
        parent = main_container,
        x = 0,
        y = 60,
        w = 320,
        h = 360,
        color = 0xF8F9FA,
    })

    -- 创建网格布局的演示按钮
    local button_width = 140
    local button_height = 70
    local columns = 2
    local padding = 10
    local y_offset = 0
    
    for i, demo in ipairs(demos) do
        local col = (i - 1) % columns
        local row = math.floor((i - 1) / columns)
        
        local x = padding + col * (button_width + padding)
        local y = y_offset + row * (button_height + padding)
        
        -- 创建按钮容器（卡片样式）
        local card = airui.container({
            parent = scroll_container,
            x = x,
            y = y,
            w = button_width,
            h = button_height,
            color = demo.color,
            radius = 8,
        })
        
        -- 图标标签
        airui.label({
            parent = card,
            text = demo.icon,
            x = 10,
            y = 15,
            w = 30,
            h = 50,
        })
        
        -- 演示名称标签
        airui.label({
            parent = card,
            text = demo.name,
            x = 50,
            y = 15,
            w = button_width - 60,
            h = 50,
            on_click = function()
            _G.show_page(demo.page) end
        })
    end

    -- 底部状态栏
    local status_bar = airui.container({
        parent = main_container,
        x = 0,
        y = 440,
        w = 320,
        h = 40,
        color = 0xCFCFCF,
    })

    airui.label({
        parent = status_bar,
        text = string.format("共%d个演示 - AirUI v1.0.3", #demos),
        x = 10,
        y = 12,
        w = 300,
        h = 16,
    })
end

-- 初始化页面
function home_page.init(params)
    home_page.create_ui()
end

-- 清理页面
function home_page.cleanup()
    -- 清理UI元素
    main_container = nil
    scroll_container = nil
end

return home_page