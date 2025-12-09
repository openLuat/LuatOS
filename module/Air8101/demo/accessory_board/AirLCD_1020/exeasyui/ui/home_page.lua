--[[
@module  home_page
@summary 主页模块，提供应用主界面和页面导航功能
@version 1.0
@date    2025.12.2
@author  江访
@usage
本文件为主页功能模块，核心业务逻辑为：
1、创建应用主窗口并配置背景颜色；
2、配置子页面工厂函数，管理各演示页面的创建；
3、创建标题和功能按钮，提供页面导航功能；
4、处理按钮点击事件，实现页面切换；

本文件的对外接口有1个：
1、home_page.create()：创建主页界面；
]]

local home_page = {}

--[[
创建主页界面；

@api home_page.create()
@summary 创建并配置应用主页面
@return nil

@usage
-- 在UI主程序中调用创建主页
home_page.create()
]]

function home_page.create()
    -- 创建主页 - 使用全屏
    local home = ui.window({ 
        background_color = ui.COLOR_WHITE,
        x = 0, y = 0, w = 800, h = 480  -- 全屏窗口
    })
    home.visible = true

    -- 配置子页面工厂
    home:configure_subpages({
        component = function() return require("component_page").create(ui) end,
        default_font = function() return require("default_font_page").create(ui) end,
        gtfont = function() return require("gtfont_page").create(ui) end,
        hzfont = function() return require("hzfont_page").create(ui) end
    })

    -- 标题 - 居中显示
    local title = ui.label({
        x = 325,           -- 居中计算: (800 - 文字宽度)/2，近似值
        y = 50,
        text = "exEasyUI演示系统",
        color = ui.COLOR_BLACK,
        size = 20          -- 增大字号
    })

    local subtitle = ui.label({
        x = 280,           -- 居中显示
        y = 80,
        text = "基于exEasyUI v1.7.0开发 - 800*480分辨率",
        color = ui.COLOR_GRAY,
        size = 14
    })

    -- 按钮布局 - 使用800宽度的新布局
    local btn_width = 340  -- 按钮宽度增大
    local btn_height = 60  -- 按钮高度增大
    local btn_x = 40       -- 左侧起始位置
    local btn_spacing = 70 -- 按钮间距

    -- 组件演示按钮
    local btn_component = ui.button({
        x = btn_x,
        y = 150,
        w = btn_width,
        h = btn_height,
        text = "组件演示",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        font_size = 16,    -- 增大按钮文字
        on_click = function()
            home:show_subpage("component")
        end
    })

    -- 默认字体演示按钮
    local btn_default_font = ui.button({
        x = btn_x + btn_width + 40,  -- 右侧按钮
        y = 150,
        w = btn_width,
        h = btn_height,
        text = "默认字体演示",
        bg_color = ui.COLOR_RED,
        text_color = ui.COLOR_WHITE,
        font_size = 16,
        on_click = function()
            home:show_subpage("default_font")
        end
    })

    -- GTFont演示按钮
    local btn_gtfont = ui.button({
        x = btn_x,
        y = 150 + btn_height + btn_spacing,
        w = btn_width,
        h = btn_height,
        text = "GTFont演示",
        bg_color = ui.COLOR_GREEN,
        text_color = ui.COLOR_WHITE,
        font_size = 16,
        on_click = function()
            home:show_subpage("gtfont")
        end
    })

    -- HZFont演示按钮
    local btn_hzfont = ui.button({
        x = btn_x + btn_width + 40,
        y = 150 + btn_height + btn_spacing,
        w = btn_width,
        h = btn_height,
        text = "HZFont演示",
        bg_color = ui.COLOR_ORANGE,
        text_color = ui.COLOR_WHITE,
        font_size = 16,
        on_click = function()
            home:show_subpage("hzfont")
        end
    })

    -- 添加所有组件到窗口
    home:add(title)
    home:add(subtitle)
    home:add(btn_component)
    home:add(btn_default_font)
    home:add(btn_gtfont)
    home:add(btn_hzfont)

    ui.add(home)
end

return home_page