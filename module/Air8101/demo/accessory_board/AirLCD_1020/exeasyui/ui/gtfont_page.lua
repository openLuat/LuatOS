--[[
@module  gtfont_page
@summary GTFont矢量字体演示页面模块，展示AirFONTS_1000配件板字体功能
@version 1.0
@date    2025.12.2
@author  江访
@usage
本文件为GTFont矢量字体演示页面功能模块，核心业务逻辑为：
1、创建带上下滚动功能的演示窗口，展示GTFont矢量字体特性；
2、演示动态字体大小调整功能，展示的是16-48号字体切换，
   GTFont支持10-192号字体，demo以展示GTFont特性为主；
3、展示不同大小和颜色的数字、符号、中英文显示效果；
4、提供GTFont特性说明和返回主页的导航功能；

本文件的对外接口有1个：
1、gtfont_page.create(ui)：创建GTFont演示页面；
]]

local gtfont_page = {}
local demo_state = {
    current_size = 24
}

--[[
创建GTFont矢量字体演示页面；

@api gtfont_page.create(ui)
@summary 创建GTFont矢量字体演示页面界面
@table ui UI库对象
@return table GTFont演示窗口对象

@usage
-- 在子页面工厂中调用创建GTFont演示页面
local gtfont_page = require("gtfont_page").create(ui)
]]
function gtfont_page.create(ui)
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
    
    -- 标题 - 增大字体并居中显示
    local title = ui.label({
        x = 200, y = 30,  -- 调整位置
        text = "GTFont矢量字体演示",
        color = ui.COLOR_BLACK,
        size = 32
    })
    
    -- 返回按钮 - 增大按钮尺寸
    local btn_back = ui.button({
        x = 30, y = 30,
        w = 100, h = 50,
        text = "返回主页",
        size = 20,
        on_click = function()
            win:back()
        end
    })
    
    -- 动态字体大小演示区域
    local dynamic_title = ui.label({
        x = 50, y = 100,
        text = "GTFont动态字体大小调整演示:",
        color = ui.COLOR_BLACK,
        size = 24
    })
    
    -- 当前字体显示
    local size_display = ui.label({
        x = 50, y = 150,
        text = "当前字体: 24号 蓝色矢量字体",
        color = ui.COLOR_BLUE,
        size = 24
    })
    
    -- 字体大小控制按钮
    local btn_increase = ui.button({
        x = 50, y = 200,
        w = 200, h = 50,
        text = "点击切换字体大小 (16-48)",
        size = 20,  
        on_click = function()
            demo_state.current_size = demo_state.current_size + 8 
            if demo_state.current_size > 48 then
                demo_state.current_size = 16  
            end
            -- 同时更新文本和大小
            size_display:set_text("当前字体: " .. demo_state.current_size .. "号 蓝色矢量字体")
            size_display:set_size(demo_state.current_size)
        end
    })
    
    -- 字体演示标题
    local demo_title = ui.label({
        x = 50, y = 280,
        text = "字体效果演示:",
        color = ui.COLOR_BLACK,
        size = 28
    })
    
    -- 数字演示 - 蓝色
    local number_demo = ui.label({
        x = 50, y = 330,
        text = "1、数字演示: 0123456789",
        color = ui.COLOR_BLUE,
        size = 22  
    })
    
    -- 符号演示 - 橙色
    local symbol_demo = ui.label({
        x = 50, y = 380,
        text = "2、符号演示: !@#$%^&*()_+-=[]{}|;:,.<>?/~`",
        color = ui.COLOR_ORANGE,
        size = 26
    })
    
    -- 中英文演示 - 红色，增大字体
    local text_demo = ui.label({
        x = 50, y = 440,
        text = "3、中英文演示: LuatOS 嵌入式系统",
        color = ui.COLOR_RED,
        size = 36
    })
    
    -- 中文演示 - 绿色
    local chinese_demo = ui.label({
        x = 50, y = 500,
        text = "4、中文演示: 矢量字体显示效果测试",
        color = ui.COLOR_GREEN,
        size = 32
    })
    
    -- GTFont特性说明
    local feature_title = ui.label({
        x = 50, y = 580,
        text = "GTFont矢量字体特性:",
        color = ui.COLOR_BLACK,
        size = 28
    })
    
    -- 特性说明使用增大字体
    local feature1 = ui.label({
        x = 70, y = 630,
        text = "-使用AirFONTS_1000配件板",
        color = ui.COLOR_DARK_GRAY,
        size = 20  
    })
    
    local feature2 = ui.label({
        x = 70, y = 670,
        text = "-支持10到192号的黑体矢量字体",
        color = ui.COLOR_DARK_GRAY,
        size = 20
    })
    
    local feature3 = ui.label({
        x = 70, y = 710,
        text = "-支持GBK中文和ASCII码字符集",
        color = ui.COLOR_DARK_GRAY,
        size = 20
    })
    
    local feature4 = ui.label({
        x = 70, y = 750,
        text = "-支持灰度显示，字体边缘更平滑",
        color = ui.COLOR_DARK_GRAY,
        size = 20
    })
    
    local feature5 = ui.label({
        x = 70, y = 790,
        text = "-无级缩放，任意大小都清晰",
        color = ui.COLOR_DARK_GRAY,
        size = 20
    })
    
    
    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    win:add(dynamic_title)
    win:add(size_display)
    win:add(btn_increase)
    win:add(demo_title)
    win:add(number_demo)
    win:add(symbol_demo)
    win:add(text_demo)
    win:add(chinese_demo)
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)
    win:add(feature3)
    win:add(feature4)
    win:add(feature5)
    
    return win
end

return gtfont_page