--[[
@module  default_font_page
@summary 默认字体演示页面模块（480×854竖屏适配版）
@version 1.0
@date    2026.01.26
@author  江访
@usage
本文件为默认字体演示页面功能模块，已适配480×854竖屏分辨率：
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

function default_font_page.create()
        local win = ui.window({
        background_color = ui.COLOR_WHITE,
        x = 0,
        y = 0,
        w = 480,
        h = 854
    })

    -- 标题（居中显示）
    local title = ui.label({
        x = 140,
        y = 30,
        text = "默认字体演示",
        color = ui.COLOR_BLACK,
        size = 32
    })

    -- 返回按钮（左上角）
    local btn_back = ui.button({
        x = 20,
        y = 25,
        w = 80,
        h = 50,
        text = "返回",
        text_size = 18,
        on_click = function()
            win:back()
        end
    })

    -- 字体信息说明
    local info_label = ui.label({
        x = 40,
        y = 90,
        text = "使用内置12号点阵字体",
        color = ui.COLOR_DARK_BLUE,
        size = 22
    })

    -- ==================== 字体演示区域 ====================
    -- 区域标题
    local demo_title = ui.label({
        x = 40,
        y = 140,
        text = "字体效果演示:",
        color = ui.COLOR_BLACK,
        size = 26
    })

    -- 1. 数字演示（蓝色）
    local number_label = ui.label({
        x = 60,
        y = 190,
        text = "数字:",
        color = ui.COLOR_BLACK,
        size = 20
    })

    local number_demo = ui.label({
        x = 170,
        y = 190,
        text = "0123456789",
        color = ui.COLOR_BLUE,
        size = 12
    })

    -- 2. 大写字母演示（绿色）
    local uppercase_label = ui.label({
        x = 60,
        y = 230,
        text = "大写字母:",
        color = ui.COLOR_BLACK,
        size = 20
    })

    local uppercase_demo = ui.label({
        x = 170,
        y = 230,
        text = "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
        color = ui.COLOR_GREEN,
        size = 12
    })

    -- 3. 小写字母演示（紫色）
    local lowercase_label = ui.label({
        x = 60,
        y = 270,
        text = "小写字母:",
        color = ui.COLOR_BLACK,
        size = 20
    })

    local lowercase_demo = ui.label({
        x = 170,
        y = 270,
        text = "abcdefghijklmnopqrstuvwxyz",
        color = ui.COLOR_PURPLE,
        size = 12
    })

    -- 4. 符号演示（橙色）
    local symbol_label = ui.label({
        x = 60,
        y = 310,
        text = "特殊符号:",
        color = ui.COLOR_BLACK,
        size = 20
    })

    local symbol_demo = ui.label({
        x = 170,
        y = 310,
        text = "!@#$%^&*()_+-=[]{}|;:'\",.<>/?",
        color = ui.COLOR_ORANGE,
        size = 12
    })

    -- 5. 中英文混排演示（红色）
    local mixed_label = ui.label({
        x = 60,
        y = 350,
        text = "中英文混排:",
        color = ui.COLOR_BLACK,
        size = 20
    })

    local mixed_demo = ui.label({
        x = 170,
        y = 350,
        text = "Hello 世界! 欢迎使用LuatOS",
        color = ui.COLOR_RED,
        size = 12
    })

    -- 6. 长文本演示（深灰色）
    local paragraph_label = ui.label({
        x = 60,
        y = 390,
        text = "长文本段落:",
        color = ui.COLOR_BLACK,
        size = 20
    })

    local paragraph_demo = ui.label({
        x = 170,
        y = 390,
        w = 200,
        text = "LuatOS是运行在嵌入式硬件的实时操作系统，exEasyUI是基于LuatOS的轻量级UI框架，支持480×854竖屏显示。默认字体为12号点阵字体，大小固定。",
        color = ui.COLOR_DARK_GRAY,
        size = 12,
        word_wrap = true
    })

    -- ==================== 字体特性说明 ====================
    local feature_title = ui.label({
        x = 40,
        y = 510,
        text = "字体特性说明:",
        color = ui.COLOR_BLACK,
        size = 26
    })

    -- 特性列表
    local feature1 = ui.label({
        x = 60,
        y = 560,
        text = "- 内置12号点阵字体，无需外部字库",
        color = ui.COLOR_DARK_GREEN,
        size = 18
    })

    local feature2 = ui.label({
        x = 60,
        y = 600,
        text = "- 启动速度快，资源占用小",
        color = ui.COLOR_DARK_GREEN,
        size = 18
    })

    local feature3 = ui.label({
        x = 60,
        y = 640,
        text = "- 支持中英文和常见符号",
        color = ui.COLOR_DARK_GREEN,
        size = 18
    })

    local feature4 = ui.label({
        x = 60,
        y = 680,
        text = "- 字体大小固定，无法动态调整",
        color = ui.COLOR_ORANGE,
        size = 18
    })

    local feature5 = ui.label({
        x = 60,
        y = 720,
        text = "- 显示效果受限于点阵分辨率",
        color = ui.COLOR_ORANGE,
        size = 18
    })

    -- 按键提示信息
    local tip_label = ui.label({
        x = 40,
        y = 780,
        text = "拉高: GPIO33切换，GPIO34确认",
        color = ui.COLOR_GRAY,
        size = 12
    })

    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(info_label)
    win:add(demo_title)
    win:add(number_label)
    win:add(number_demo)
    win:add(uppercase_label)
    win:add(uppercase_demo)
    win:add(lowercase_label)
    win:add(lowercase_demo)
    win:add(symbol_label)
    win:add(symbol_demo)
    win:add(mixed_label)
    win:add(mixed_demo)
    win:add(paragraph_label)
    win:add(paragraph_demo)
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)
    win:add(feature3)
    win:add(feature4)
    win:add(feature5)
    win:add(tip_label)
    
    return win
end

return default_font_page