--[[
@module  home_page
@summary 主页模块，提供应用主界面和页面导航功能
@version 1.0
@date    2026.01.23
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
    -- 创建主页 - 使用全屏竖屏
    local page_w, page_h = lcd.getSize()
    local home = ui.window({ 
        background_color = ui.COLOR_WHITE,
        x = 0, y = 0, w = page_w, h = page_h  -- 竖屏全屏窗口
    })
    home.visible = true

    -- 配置子页面工厂
    home:configure_subpages({
        component = function() return require("component_page").create(ui) end,
        default_font = function() return require("default_font_page").create(ui) end,
        hzfont = function() return require("hzfont_page").create(ui) end
    })

    -- 标题 - 居中显示
    local title = ui.label({
        x = 200,           -- 居中计算: (720 - 400)/2，近似值
        y = 80,
        text = "exEasyUI演示系统",
        color = ui.COLOR_BLACK,
        size = 32          -- 增大字号
    })

    local subtitle = ui.label({
        x = 160,           -- 居中显示
        y = 120,
        text = "基于exEasyUI v1.7.0开发 - 720*1280分辨率",
        color = ui.COLOR_GRAY,
        size = 18
    })

    -- 按钮布局 - 竖屏布局（单列）
    local btn_width = 400   -- 按钮宽度
    local btn_height = 70   -- 按钮高度
    local start_y = 200     -- 起始Y坐标
    local btn_spacing = 30  -- 按钮间距

    -- 组件演示按钮
    local btn_component = ui.button({
        x = (720 - btn_width) / 2,  -- 居中
        y = start_y,
        w = btn_width,
        h = btn_height,
        text = "组件演示",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        text_size = 24,
        on_click = function()
            home:show_subpage("component")
        end
    })

    -- 默认字体演示按钮
    local btn_default_font = ui.button({
        x = (720 - btn_width) / 2,  -- 居中
        y = start_y + (btn_height + btn_spacing) * 1,
        w = btn_width,
        h = btn_height,
        text = "默认字体演示",
        bg_color = ui.COLOR_RED,
        text_color = ui.COLOR_WHITE,
        text_size = 24,
        on_click = function()
            home:show_subpage("default_font")
        end
    })

    -- HZFont演示按钮
    local btn_hzfont = ui.button({
        x = (720 - btn_width) / 2,  -- 居中
        y = start_y + (btn_height + btn_spacing) * 2,
        w = btn_width,
        h = btn_height,
        text = "HZFont演示",
        bg_color = ui.COLOR_ORANGE,
        text_color = ui.COLOR_WHITE,
        text_size = 24,
        on_click = function()
            home:show_subpage("hzfont")
        end
    })

    -- 添加所有组件到窗口
    home:add(title)
    home:add(subtitle)
    home:add(btn_component)
    home:add(btn_default_font)
    home:add(btn_hzfont)

    ui.add(home)
end

return home_page