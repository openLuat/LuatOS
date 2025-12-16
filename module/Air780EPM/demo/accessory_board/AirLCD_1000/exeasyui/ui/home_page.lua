--[[
@module  home_page
@summary 主页模块，提供应用主界面和页面导航功能
@version 1.0
@date    2025.12.10
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
    -- 创建主页
    local home = ui.window({ background_color = ui.COLOR_WHITE })
    home.visible = true

    -- 配置子页面工厂
    home:configure_subpages({
        component = function() return require("component_page").create(ui) end,
        default_font = function() return require("default_font_page").create(ui) end,
    })

    -- 标题
    local title = ui.label({
        x = 80,
        y = 30,
        text = "exEasyUI v1.7.0 Demo System",
        color = ui.COLOR_BLACK,
        size = 12
    })

    local subtitle = ui.label({
        x = 80,
        y = 60,
        text = "boot: Select  pwr: Confirm",
        color = ui.COLOR_GRAY,
        size = 12
    })

    -- 组件演示按钮
    local btn_component = ui.button({
        x = 20,
        y = 100,
        w = 280,
        h = 50,
        text = "Component Demo",
        bg_color = ui.COLOR_BLUE,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            home:show_subpage("component")
        end
    })

    -- 默认字体演示按钮
    local btn_default_font = ui.button({
        x = 20,
        y = 170,
        w = 280,
        h = 50,
        text = "Default Font Demo",
        bg_color = ui.COLOR_RED,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            home:show_subpage("default_font")
        end
    })


    -- 添加所有组件到窗口
    home:add(title)
    home:add(subtitle)
    home:add(btn_component)
    home:add(btn_default_font)

    ui.add(home)
end

return home_page