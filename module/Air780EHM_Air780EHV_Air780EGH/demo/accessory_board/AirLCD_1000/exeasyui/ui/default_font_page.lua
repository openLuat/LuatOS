--[[
@module  default_font_page
@summary 默认字体演示页面模块
@version 1.0
@date    2025.12.3
@author  江访
@usage
本文件为默认字体演示页面功能模块，核心业务逻辑为：
1、创建演示窗口，展示内置12号点阵字体的固定大小特性；
2、演示数字、符号、中英文混排的显示效果；
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
        x = 0,
        y = 0,
        w = 320,
        h = 480
    })

    -- 标题
    local title = ui.label({
        x = 120,
        y = 25,
        text = "默认字体演示",
        color = ui.COLOR_BLACK,
        size = 12
    })

    -- 返回按钮
    local btn_back = ui.button({
        x = 20,
        y = 20,
        w = 60,
        h = 30,
        text = "返回",
        on_click = function()
            win:back()
        end
    })

    -- 字体演示标题
    local demo_title = ui.label({
        x = 20,
        y = 70,
        text = "字体演示 (固定12号):",
        color = ui.COLOR_BLACK,
        size = 12
    })

    -- 数字演示
    local number_demo = ui.label({
        x = 20,
        y = 100,
        text = "1、数字: 0123456789",
        color = ui.COLOR_BLUE,
        size = 12
    })

    -- 符号演示
    local symbol_demo = ui.label({
        x = 20,
        y = 130,
        text = "2、符号: !@#$%^&*()_+-=[]",
        color = ui.COLOR_ORANGE,
        size = 12
    })

    -- 中英文演示
    local text_demo = ui.label({
        x = 20,
        y = 160,
        text = "3、中英文: Hello 世界 ABC",
        color = ui.COLOR_RED,
        size = 12
    })

    -- 默认字体特性说明
    local feature_title = ui.label({
        x = 20,
        y = 200,
        text = "默认字体特性:",
        color = ui.COLOR_BLACK,
        size = 12
    })

    local feature1 = ui.label({
        x = 20,
        y = 230,
        text = "- 内置12号点阵字体",
        color = ui.COLOR_GRAY,
        size = 12
    })

    local feature2 = ui.label({
        x = 20,
        y = 260,
        text = "- 无需外部硬件支持",
        color = ui.COLOR_GRAY,
        size = 12
    })

    local feature3 = ui.label({
        x = 20,
        y = 290,
        text = "- 启动快速，资源占用小",
        color = ui.COLOR_GRAY,
        size = 12
    })

    local feature4 = ui.label({
        x = 20,
        y = 320,
        text = "- 字体大小固定为12号",
        color = ui.COLOR_GRAY,
        size = 12
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