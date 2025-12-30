--[[
@module  default_font_page
@summary 默认字体演示页面模块，使用内置12号英文点阵字体
@version 1.0
@date    2025.12.10
@author  江访
@usage
本文件为默认字体演示页面功能模块，核心业务逻辑为：
1、创建演示窗口，展示内置12号英文点阵字体的固定大小特性；
2、演示数字、符号、英文的显示效果；
3、展示默认字体的特性和限制说明；
4、提供返回主页的导航功能；

本文件的对外接口有1个：
1、default_font_page.create(ui)：创建默认字体演示页面；
]]

local default_font_page = {}

--[[
创建默认字体演示页面；

@api default_font_page.create(ui)
@summary 创建默认字体演示页面界面
@table ui UI库对象
@return table 默认字体演示窗口对象

@usage
-- 在子页面工厂中调用创建默认字体演示页面
local default_font_page = require("default_font_page").create(ui)
]]
function default_font_page.create(ui)
    local win = ui.window({ 
        background_color = ui.COLOR_WHITE,
        x = 0, y = 0, w = 320, h = 480
    })
    
    -- 标题 - 居中显示
    local title = ui.label({
        x = 120, y = 25,
        text = "Default Font Demo",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    -- 返回按钮
    local btn_back = ui.button({
        x = 20, y = 20,
        w = 60, h = 30,
        text = "Back",
        on_click = function()
            win:back()
        end
    })
    
    -- 字体演示标题
    local demo_title = ui.label({
        x = 20, y = 70,
        text = "Font Demo (Fixed 12pt):",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    -- 数字演示 - 蓝色12号
    local number_demo = ui.label({
        x = 20, y = 100,
        text = "1. Numbers: 0123456789",
        color = ui.COLOR_BLUE,
        size = 12
    })
    
    -- 符号演示 - 橙色12号
    local symbol_demo = ui.label({
        x = 20, y = 130,
        text = "2. Symbols: !@#$%^&*()_+-=[]",
        color = ui.COLOR_ORANGE,
        size = 12
    })
    
    -- 英文演示 - 红色12号
    local text_demo = ui.label({
        x = 20, y = 160,
        text = "3. English: Hello World ABC",
        color = ui.COLOR_RED,
        size = 12
    })
    
    -- 默认字体特性说明
    local feature_title = ui.label({
        x = 20, y = 200,
        text = "Default Font Features:",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local feature1 = ui.label({
        x = 20, y = 230,
        text = "- Built-in 12pt bitmap font",
        color = ui.COLOR_GRAY,
        size = 12
    })
    
    local feature2 = ui.label({
        x = 20, y = 260,
        text = "- Supports English, numbers, symbols",
        color = ui.COLOR_GRAY,
        size = 12
    })
    
    local feature3 = ui.label({
        x = 20, y = 290,
        text = "- Fast startup, low resource usage",
        color = ui.COLOR_GRAY,
        size = 12
    })
    
    local feature4 = ui.label({
        x = 20, y = 320,
        text = "- Fixed 12pt font size",
        color = ui.COLOR_GRAY,
        size = 12
    })
    
    -- 启用滚动以显示完整内容
    win:enable_scroll({
        direction = "vertical",
        content_height = 400,
        threshold = 10
    })
    
    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(demo_title)
    win:add(number_demo)
    win:add(symbol_demo)
    win:add(text_demo)
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)
    win:add(feature3)
    win:add(feature4)
    
    return win
end

return default_font_page