--[[
@module hzfont_page
@summary HZFont矢量字体演示页面模块（480×854竖屏适配版）
@version 1.0
@date 2026.01.26
@author 江访
@usage
本文件为HZFont矢量字体演示页面模块，已适配480×854竖屏分辨率：
1、创建HZFont矢量字体演示页面，展示矢量字体的动态调整能力；
2、演示多种字体大小和颜色的文本显示效果；
3、提供字体大小动态切换功能，展示矢量字体的缩放优势；
4、展示HZFont矢量字体的特性和应用场景；

本文件的对外接口有1个：
1、hzfont_page.create(ui)：创建并返回HZFont演示窗口；
]]

local hzfont_page = {}

--[[
页面演示状态记录表

@table demo_state
@field current_size number 当前演示字体大小，初始值为16号
]]
local demo_state = {
    current_size = 16 -- 当前字体大小，从16号开始
}

--[[
创建HZFont矢量字体演示页面窗口；

@api hzfont_page.create(ui)

@summary 创建HZFont矢量字体演示页面

@param ui table exEasyUI库对象，用于创建UI组件

@return table 返回创建的窗口对象

@usage
-- 在页面切换逻辑中调用
local hzfont_win = hzfont_page.create(ui)
return hzfont_win
]]
function hzfont_page.create()
    local win = ui.window({
        background_color = ui.COLOR_WHITE,
        x = 0,
        y = 0,
        w = 480,
        h = 854
    })


    local title = ui.label({
        x = 120,
        y = 30,
        text = "HZFont矢量字体演示",
        color = ui.COLOR_BLACK,
        size = 32
    })


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


    local dynamic_title = ui.label({
        x = 40,
        y = 100,
        text = "动态字体大小调整:",
        color = ui.COLOR_BLACK,
        size = 26
    })


    local size_info = ui.label({
        x = 40,
        y = 150,
        text = "当前字体大小: 16号",
        color = ui.COLOR_BLUE,
        size = 16
    })


    local btn_increase = ui.button({
        x = 40,
        y = 200,
        w = 150,
        h = 55,
        text = "增大字体",
        text_size = 18,
        bg_color = ui.COLOR_GREEN,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            -- 每次点击增加4号字体大小
            demo_state.current_size = demo_state.current_size + 4

            -- 当字体大小超过32号时，重置为12号
            if demo_state.current_size > 32 then
                demo_state.current_size = 12
                -- 更新标签文本和字体大小
                size_info:set_text("当前字体大小: 12号")
                size_info:set_size(12)
            else
                -- 更新标签文本和字体大小
                size_info:set_text("当前字体大小: " .. demo_state.current_size .. "号")
                size_info:set_size(demo_state.current_size)
            end
        end
    })

    -- 减小字体按钮
    local btn_decrease = ui.button({
        x = 210,
        y = 200,
        w = 150,
        h = 55,
        text = "减小字体",
        text_size = 18,
        bg_color = ui.COLOR_ORANGE,
        text_color = ui.COLOR_WHITE,
        on_click = function()
            -- 每次点击减小4号字体大小
            demo_state.current_size = demo_state.current_size - 4

            -- 当字体大小小于12号时，重置为32号
            if demo_state.current_size < 12 then
                demo_state.current_size = 32
                -- 更新标签文本和字体大小
                size_info:set_text("当前字体大小: 32号")
                size_info:set_size(32)
            else
                -- 更新标签文本和字体大小
                size_info:set_text("当前字体大小: " .. demo_state.current_size .. "号")
                size_info:set_size(demo_state.current_size)
            end
        end
    })


    local demo_title = ui.label({
        x = 40,
        y = 280,
        text = "多尺寸字体演示:",
        color = ui.COLOR_BLACK,
        size = 26
    })


    local small_demo = ui.label({
        x = 40,
        y = 330,
        text = "12号字体: HZFont矢量字库",
        color = ui.COLOR_DARK_BLUE,
        size = 12
    })


    local medium_demo = ui.label({
        x = 40,
        y = 370,
        text = "18号字体: 支持平滑缩放!",
        color = ui.COLOR_GREEN,
        size = 18
    })


    local large_demo = ui.label({
        x = 40,
        y = 420,
        text = "24号字体: LuatOS嵌入式系统",
        color = ui.COLOR_RED,
        size = 24
    })


    local xlarge_demo = ui.label({
        x = 40,
        y = 480,
        text = "32号字体: 480×854竖屏",
        color = ui.COLOR_PURPLE,
        size = 32
    })


    local paragraph_demo = ui.label({
        x = 40,
        y = 540,
        w = 400,
        text = "HZFont是合宙内置的矢量字库，支持12-255号字体动态调整，无需外部硬件支持。矢量字体可以平滑缩放，在不同分辨率下都能保持清晰显示效果，特别适合需要多种字体大小的应用场景。",
        color = ui.COLOR_DARK_GRAY,
        size = 16,
        word_wrap = true
    })


    local feature_title = ui.label({
        x = 40,
        y = 620,
        text = "HZFont特性:",
        color = ui.COLOR_BLACK,
        size = 26
    })


    local feature1 = ui.label({
        x = 60,
        y = 670,
        text = "- 内置矢量字体，无需外部硬件",
        color = ui.COLOR_DARK_GREEN,
        size = 18
    })


    local feature2 = ui.label({
        x = 60,
        y = 710,
        text = "- 支持12-255号字体动态调整",
        color = ui.COLOR_DARK_GREEN,
        size = 18
    })


    local feature3 = ui.label({
        x = 60,
        y = 750,
        text = "- 平滑缩放，显示效果优秀",
        color = ui.COLOR_DARK_GREEN,
        size = 18
    })

    -- 按键操作提示
    local tip_label = ui.label({
        x = 100,
        y = 800,
        text = "上拉: GPIO33切换，GPIO34确认",
        color = ui.COLOR_GRAY,
        size = 16
    })


    win:add(title)
    win:add(btn_back)
    win:add(dynamic_title)
    win:add(size_info)
    win:add(btn_increase)
    win:add(btn_decrease)
    win:add(demo_title)
    win:add(small_demo)
    win:add(medium_demo)
    win:add(large_demo)
    win:add(xlarge_demo)
    win:add(paragraph_demo)
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)
    win:add(feature3)
    win:add(tip_label)

    return win
end

return hzfont_page
