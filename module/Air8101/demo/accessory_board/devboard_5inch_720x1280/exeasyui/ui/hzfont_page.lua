--[[
@module  hzfont_page
@summary HZFont矢量字体演示页面模块，展示内置HZFont矢量字体功能
@version 1.0
@date    2026.01.23
@author  江访
@usage
已适配720*1280竖屏分辨率
]]

local hzfont_page = {}
local demo_state = {
    current_size = 24,
    font_sizes = {12, 16, 20, 24, 32, 40, 48, 64, 80, 100},
    current_size_index = 4
}

function hzfont_page.create(ui)
    local win = ui.window({ 
        background_color = ui.COLOR_WHITE,
        x = 0, y = 0, w = 720, h = 1280
    })
    
    -- 启用滚动
    win:enable_scroll({
        direction = "vertical",
        content_height = 1600,
        threshold = 10
    })
    
    -- 标题
    local title = ui.label({
        x = 160, y = 40,
        text = "HZFont矢量字体演示",
        color = ui.COLOR_BLUE,
        size = 32
    })
    
    -- 返回按钮
    local btn_back = ui.button({
        x = 20, y = 30,
        w = 120, h = 55,
        text = "返回主页",
        size = 20,
        on_click = function()
            win:back()
        end
    })
    
    -- 动态字体大小演示区域
    local dynamic_title = ui.label({
        x = 40, y = 120,
        text = "HZFont动态字体大小调整演示:",
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    -- 当前字体显示
    local size_display = ui.label({
        x = 40, y = 170,
        text = "当前字体: 24号 蓝色矢量字体",
        color = ui.COLOR_BLUE,
        size = 24
    })
    
    -- 字体大小控制按钮
    local btn_increase = ui.button({
        x = 400, y = 100,
        w = 300, h = 60,
        text = "点击切换字体大小 (12-100)",
        size = 20,  
        on_click = function()
            demo_state.current_size_index = demo_state.current_size_index + 1
            if demo_state.current_size_index > #demo_state.font_sizes then
                demo_state.current_size_index = 1
            end
            demo_state.current_size = demo_state.font_sizes[demo_state.current_size_index]
            
            size_display:set_text("当前字体: " .. demo_state.current_size .. "号 蓝色矢量字体")
            size_display:set_size(demo_state.current_size)
        end
    })
    
    -- 字体演示标题
    local demo_title = ui.label({
        x = 40, y = 320,
        text = "HZFont字体效果演示:",
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    -- 不同大小字体演示
    local size_demo1 = ui.label({
        x = 40, y = 370,
        text = "12号字体: HZFont演示",
        color = ui.COLOR_BLACK,
        size = 12
    })
    
    local size_demo2 = ui.label({
        x = 40, y = 400,
        text = "20号字体: HZFont演示",
        color = ui.COLOR_BLUE,
        size = 20
    })
    
    local size_demo3 = ui.label({
        x = 40, y = 440,
        text = "32号字体: HZFont演示",
        color = ui.COLOR_RED,
        size = 32
    })
    
    local size_demo4 = ui.label({
        x = 40, y = 500,
        text = "48号字体: 大字体演示",
        color = ui.COLOR_GREEN,
        size = 48
    })
    
    -- 中文演示
    local chinese_demo = ui.label({
        x = 40, y = 580,
        text = "中文演示: 矢量字体显示效果",
        color = ui.COLOR_PURPLE,
        size = 28
    })
    
    -- 中英文混排演示
    local mix_demo = ui.label({
        x = 40, y = 630,
        text = "中英文混排: Hello World!",
        color = ui.COLOR_DARK_BLUE,
        size = 24
    })
    
    -- HZFont特性说明
    local feature_title = ui.label({
        x = 40, y = 700,
        text = "HZFont矢量字体特性:",
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    local feature1 = ui.label({
        x = 60, y = 750,
        text = "-文件系统烧录字体，无需外部硬件",
        color = ui.COLOR_DARK_GRAY,
        size = 18
    })
    
    local feature2 = ui.label({
        x = 60, y = 790,
        text = "-支持任意2MB内.ttf字体",
        color = ui.COLOR_DARK_GRAY,
        size = 18
    })
    
    local feature3 = ui.label({
        x = 60, y = 830,
        text = "-支持12到255号字体大小",
        color = ui.COLOR_DARK_GRAY,
        size = 18
    })
    
    local feature4 = ui.label({
        x = 60, y = 870,
        text = "-无级缩放，边缘平滑",
        color = ui.COLOR_DARK_GRAY,
        size = 18
    })
    
    local feature5 = ui.label({
        x = 60, y = 910,
        text = "-支持中英文、数字、符号混合显示",
        color = ui.COLOR_DARK_GRAY,
        size = 18
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