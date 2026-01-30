--[[
@module  default_font_page
@summary 默认字体演示页面模块，使用内置12号点阵字体功能
@version 1.0
@date    2025.12.2
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

function default_font_page.create(ui)
    local win = ui.window({ 
        background_color = ui.COLOR_WHITE,
        x = 0, y = 0, w = 1024, h = 600
    })
    
    -- 标题
    local title = ui.label({
        x = 380, y = 30,
        text = "默认字体演示 - 12号点阵字体",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    -- 返回按钮
    local btn_back = ui.button({
        x = 30, y = 25,
        w = 100, h = 40,
        text = "返回",
        on_click = function()
            win:back()
        end
    })
    
    -- -- ==================== 左栏：字体基础演示 ====================
    local left_column_x = 60
    
    local demo_title = ui.label({
        x = left_column_x, y = 100,
        text = "字体基础演示:",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    -- 数字演示
    local number_demo = ui.label({
        x = left_column_x, y = 135,
        text = "数字演示:",
        color = ui.COLOR_BLUE,
        size = 12
    })
    
    local number_content = ui.label({
        x = left_column_x + 90, y = 135,
        text = "0123456789",
        color = ui.COLOR_BLUE,
        size = 12
    })
    
    -- 符号演示
    local symbol_demo = ui.label({
        x = left_column_x, y = 170,
        text = "符号演示:",
        color = ui.COLOR_RED,
        size = 12
    })
    
    local symbol_content = ui.label({
        x = left_column_x + 90, y = 170,
        text = "!@#$%^&*()_+-=[]{}|;:,.<>?/",
        color = ui.COLOR_ORANGE,
        size = 12
    })
    
    -- 英文字母演示
    local letter_demo = ui.label({
        x = left_column_x, y = 205,
        text = "英文字母:",
        color = ui.COLOR_GREEN,
        size = 12
    })
    
    local letter_content = ui.label({
        x = left_column_x + 90, y = 205,
        text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        color = ui.COLOR_RED,
        size = 12
    })
    
    -- 中文演示
    local chinese_demo = ui.label({
        x = left_column_x, y = 240,
        text = "中文演示:",
        color = ui.COLOR_MAGENTA,
        size = 12
    })
    
    local chinese_content = ui.label({
        x = left_column_x + 90, y = 240,
        text = "天地玄黄宇宙洪荒日月盈昃辰宿列张",
        color = ui.COLOR_MAGENTA,
        size = 12
    })
    
    -- 中英文混排演示
    local mix_demo = ui.label({
        x = left_column_x, y = 275,
        text = "中英文混排:",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local mix_content = ui.label({
        x = left_column_x + 90, y = 275,
        text = "Hello 世界! ABC 123 测试 Test 演示 Demo",
        color = ui.COLOR_BLUE,
        size = 12
    })
    
    -- 完整句子演示
    local sentence_title = ui.label({
        x = left_column_x, y = 320,
        text = "完整句子演示:",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local sentence1 = ui.label({
        x = left_column_x, y = 345,
        text = "LuatOS是合宙通信推出的开源嵌入式物联网操作系统",
        color = ui.COLOR_GRAY,
        size = 12
    })
    
    local sentence2 = ui.label({
        x = left_column_x, y = 370,
        text = "默认字体为12号点阵字体，启动快速，资源占用小",
        color = ui.COLOR_GRAY,
        size = 12
    })
    
    local sentence3 = ui.label({
        x = left_column_x, y = 395,
        text = "支持中英文、数字和常用符号的显示",
        color = ui.COLOR_GRAY,
        size = 12
    })
    
    -- -- ==================== 右栏：字体特性说明 ====================
    local right_column_x = 560
    
    local feature_title = ui.label({
        x = right_column_x, y = 100,
        text = "默认字体特性说明:",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local feature1_title = ui.label({
        x = right_column_x + 25, y = 145,
        text = "-固定大小特性:",
        color = ui.COLOR_BLUE,
        size = 12
    })
    
    local feature1_desc = ui.label({
        x = right_column_x + 50, y = 170,
        w = 400,
        text = "内置12号点阵字体，字体大小固定为12号，不支持动态调整。",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local feature2_title = ui.label({
        x = right_column_x + 25, y = 205,
        text = "-硬件要求:",
        color = ui.COLOR_GREEN,
        size = 12
    })
    
    local feature2_desc = ui.label({
        x = right_column_x + 50, y = 230,
        w = 400,
        text = "无需外部硬件支持，完全内置于系统中，启动即用。",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local feature3_title = ui.label({
        x = right_column_x + 25, y = 265,
        text = "-性能优势:",
        color = ui.COLOR_RED,
        size = 12
    })
    
    local feature3_desc = ui.label({
        x = right_column_x + 50, y = 290,
        w = 400,
        text = "启动速度快，资源占用小，适合内存受限的嵌入式设备。",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local feature4_title = ui.label({
        x = right_column_x + 25, y = 325,
        text = "-字符集支持:",
        color = ui.COLOR_MAGENTA,
        size = 12
    })
    
    local feature4_desc = ui.label({
        x = right_column_x + 50, y = 350,
        w = 400,
        text = "支持常用中文字符、英文字母、数字和符号的显示。",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local feature5_title = ui.label({
        x = right_column_x + 25, y = 385,
        text = "-适用场景:",
        color = ui.COLOR_ORANGE,
        size = 12
    })
    
    local feature5_desc = ui.label({
        x = right_column_x + 50, y = 410,
        w = 400,
        text = "适用于需要快速启动、简单文本显示的应用场景。",
        color = ui.COLOR_BLACK,
        size = 12
    })  
   
    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    
    -- -- 左栏组件
    win:add(demo_title)
    win:add(number_demo)
    win:add(number_content)
    win:add(symbol_demo)
    win:add(symbol_content)
    win:add(letter_demo)
    win:add(letter_content)
    win:add(chinese_demo)
    win:add(chinese_content)
    win:add(mix_demo)
    win:add(mix_content)
    win:add(sentence_title)
    win:add(sentence1)
    win:add(sentence2)
    win:add(sentence3)
    
    -- 右栏组件
    win:add(feature_title)
    win:add(feature1_title)
    win:add(feature1_desc)
    win:add(feature2_title)
    win:add(feature2_desc)
    win:add(feature3_title)
    win:add(feature3_desc)
    win:add(feature4_title)
    win:add(feature4_desc)
    win:add(feature5_title)
    win:add(feature5_desc)

    
    return win
end

return default_font_page