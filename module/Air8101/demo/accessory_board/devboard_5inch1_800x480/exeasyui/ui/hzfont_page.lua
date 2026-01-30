--[[
@module  hzfont_page
@summary HZFont矢量字体演示页面模块，展示内置HZFont矢量字体功能
@version 1.0
@date    2026.01.23
@author  江访
@usage
本文件为HZFont矢量字体演示页面功能模块，核心业务逻辑为：
1、创建带上下滚动功能的演示窗口，展示HZFont矢量字体特性；
2、演示动态字体大小调整功能，支持12-255号字体切换；
3、展示不同大小和颜色的数字、符号、中英文显示效果；
4、提供HZFont特性说明和返回主页的导航功能；

本文件的对外接口有1个：
1、hzfont_page.create(ui)：创建HZFont演示页面；
]]

local hzfont_page = {}
local demo_state = {
    current_size = 24,
    font_sizes = {12, 16, 20, 24, 32, 40, 48, 64, 80, 100},
    current_size_index = 4
}

--[[
创建HZFont矢量字体演示页面；

@api hzfont_page.create(ui)
@summary 创建HZFont矢量字体演示页面界面
@table ui UI库对象
@return table HZFont演示窗口对象

@usage
-- 在子页面工厂中调用创建HZFont演示页面
local hzfont_page = require("hzfont_page").create(ui)
]]
function hzfont_page.create(ui)
    local win = ui.window({ 
        background_color = ui.COLOR_WHITE,
        x = 0, y = 0, w = 800, h = 480
    })
    
    -- 启用滚动以容纳更多内容
    win:enable_scroll({
        direction = "vertical",
        content_height = 900,
        threshold = 10
    })
    
    -- 标题 - 居中显示
    local title = ui.label({
        x = 200, y = 30,
        text = "HZFont矢量字体演示",
        color = ui.COLOR_BLUE,
        size = 32
    })
    
    -- 返回按钮
    local btn_back = ui.button({
        x = 30, y = 30,
        w = 100, h = 40,
        text = "返回主页",
        size = 20,
        on_click = function()
            win:back()
        end
    })
    
    -- 动态字体大小演示区域
    local dynamic_title = ui.label({
        x = 50, y = 100,
        text = "HZFont动态字体大小调整演示:",
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    -- 当前字体显示
    local size_display = ui.label({
        x = 50, y = 140,
        text = "当前字体: 24号 蓝色矢量字体",
        color = ui.COLOR_BLUE,
        size = 24
    })
    
    -- 字体大小控制按钮
    local btn_increase = ui.button({
        x = 400, y = 100,
        w = 200, h = 40,
        text = "点击切换字体大小 (12-100)",
        size = 18,  
        on_click = function()
            demo_state.current_size_index = demo_state.current_size_index + 1
            if demo_state.current_size_index > #demo_state.font_sizes then
                demo_state.current_size_index = 1
            end
            demo_state.current_size = demo_state.font_sizes[demo_state.current_size_index]
            
            -- 更新显示
            size_display:set_text("当前字体: " .. demo_state.current_size .. "号 蓝色矢量字体")
            size_display:set_size(demo_state.current_size)
        end
    })
    
    -- 字体演示标题
    local demo_title = ui.label({
        x = 50, y = 260,
        text = "HZFont字体效果演示:",
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    -- 不同大小字体演示（因为屏幕较小，我们减少一些演示行数，调整位置）
    local size_demo1 = ui.label({
        x = 50, y = 300,
        text = "12号字体: HZFont演示",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local size_demo2 = ui.label({
        x = 50, y = 325,
        text = "20号字体: HZFont演示",
        color = ui.COLOR_BLUE,
        size = 20
    })
    
    local size_demo3 = ui.label({
        x = 50, y = 360,
        text = "32号字体: HZFont演示",
        color = ui.COLOR_RED,
        size = 32
    })
    
    local size_demo4 = ui.label({
        x = 50, y = 410,
        text = "48号字体: 大字体演示",
        color = ui.COLOR_GREEN,
        size = 48
    })
    
    -- 中文演示
    local chinese_demo = ui.label({
        x = 50, y = 480,
        text = "中文演示: 矢量字体显示效果",
        color = ui.COLOR_PURPLE,
        size = 28
    })
    
    -- 中英文混排演示
    local mix_demo = ui.label({
        x = 50, y = 520,
        text = "中英文混排: Hello World!",
        color = ui.COLOR_DARK_BLUE,
        size = 20
    })
    
    -- HZFont特性说明
    local feature_title = ui.label({
        x = 50, y = 570,
        text = "HZFont矢量字体特性:",
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    local feature1 = ui.label({
        x = 70, y = 610,
        text = "-文件系统烧录字体，无需外部硬件",
        color = ui.COLOR_DARK_GRAY,
        size = 16
    })
    
    local feature2 = ui.label({
        x = 70, y = 640,
        text = "-支持任意2MB内.ttf字体",
        color = ui.COLOR_DARK_GRAY,
        size = 16
    })
    
    local feature3 = ui.label({
        x = 70, y = 670,
        text = "-支持12到255号字体大小",
        color = ui.COLOR_DARK_GRAY,
        size = 16
    })
    
    local feature4 = ui.label({
        x = 70, y = 700,
        text = "-无级缩放，边缘平滑",
        color = ui.COLOR_DARK_GRAY,
        size = 16
    })
    
    local feature5 = ui.label({
        x = 70, y = 730,
        text = "-支持中英文、数字、符号混合显示",
        color = ui.COLOR_DARK_GRAY,
        size = 16
    })

    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(dynamic_title)
    win:add(size_display)
    win:add(btn_increase)
    win:add(demo_title)
    win:add(size_demo1)
    win:add(size_demo2)
    win:add(size_demo3)
    win:add(size_demo4)
    win:add(chinese_demo)
    win:add(mix_demo)
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)
    win:add(feature3)
    win:add(feature4)
    win:add(feature5)
    
    return win
end

return hzfont_page