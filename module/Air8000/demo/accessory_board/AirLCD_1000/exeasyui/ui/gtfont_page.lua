--[[
@module  gtfont_page
@summary GTFont矢量字体演示页面模块
@version 1.0
@date    2025.12.3
@author  江访
@usage
本文件为GTFont矢量字体演示页面功能模块，核心业务逻辑为：
1、创建带上下滚动功能的演示窗口，展示GTFont矢量字体特性；
2、演示动态字体大小调整功能，展示的是12-32号字体切换，
   GTFont支持10-192号字体，demo以展示GTFont特性为主；
3、展示不同大小和颜色的数字、符号、中英文显示效果；
4、提供GTFont特性说明和返回主页的导航功能；

本文件的对外接口有1个：
1、gtfont_page.create(ui)：创建GTFont演示页面；
]]

local gtfont_page = {}
local demo_state = {
    current_size = 16
}

function gtfont_page.create(ui)
    local win = ui.window({
        background_color = ui.COLOR_WHITE,
        x = 0,
        y = 0,
        w = 320,
        h = 480
    })

    -- 标题
    local title = ui.label({
        x = 85,
        y = 25,
        text = "GTFont矢量字体演示",
        color = ui.COLOR_BLACK,
        size = 16
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

    -- 动态字体大小演示区域
    local dynamic_title = ui.label({
        x = 20,
        y = 70,
        text = "动态字体大小调整:",
        color = ui.COLOR_BLACK,
        size = 16
    })

    local size_display = ui.label({
        x = 20,
        y = 100,
        text = "当前字体: 16号 蓝色",
        color = ui.COLOR_BLUE,
        size = 16
    })

    local btn_change = ui.button({
        x = 20,
        y = 140,
        w = 120,
        h = 30,
        text = "切换字体大小",
        on_click = function()
            demo_state.current_size = demo_state.current_size + 4
            if demo_state.current_size > 32 then
                demo_state.current_size = 12
            end
            size_display:set_text("当前字体: " .. demo_state.current_size .. "号 蓝色")
            size_display:set_size(demo_state.current_size)
        end
    })

    -- 字体演示标题
    local demo_title = ui.label({
        x = 20,
        y = 180,
        text = "字体演示:",
        color = ui.COLOR_BLACK,
        size = 16
    })

    -- 数字演示
    local number_demo = ui.label({
        x = 20,
        y = 210,
        text = "数字: 0123456789",
        color = ui.COLOR_BLUE,
        size = 14
    })

    -- 符号演示
    local symbol_demo = ui.label({
        x = 20,
        y = 250,
        text = "符号: !@#$%^&*()_+-=[]",
        color = ui.COLOR_ORANGE,
        size = 20
    })

    -- 中英文演示
    local text_demo = ui.label({
        x = 20,
        y = 300,
        text = "中英文: LuatOS",
        color = ui.COLOR_RED,
        size = 28
    })

    -- 特性说明
    local feature_title = ui.label({
        x = 20,
        y = 350,
        text = "GTFont特性:",
        color = ui.COLOR_BLACK,
        size = 14
    })

    local feature1 = ui.label({
        x = 20,
        y = 380,
        text = "- 使用AirFONTS_1000配件板",
        color = ui.COLOR_GRAY,
        size = 12
    })

    local feature2 = ui.label({
        x = 20,
        y = 410,
        text = "- 支持10到192号黑体字体",
        color = ui.COLOR_GRAY,
        size = 12
    })

    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(dynamic_title)
    win:add(size_display)
    win:add(btn_change)
    win:add(demo_title)
    win:add(number_demo)
    win:add(symbol_demo)
    win:add(text_demo)
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)

    return win
end

return gtfont_page