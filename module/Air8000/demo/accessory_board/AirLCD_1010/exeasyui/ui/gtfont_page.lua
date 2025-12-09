--[[
@module  gtfont_page
@summary GTFont矢量字体演示页面模块，展示AirFONTS_1000配件板字体功能
@version 1.0
@date    2025.11.25
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
        x = 0, y = 0, w = 320, h = 600
    })
    
    -- 启用滚动以容纳更多内容
    win:enable_scroll({
        direction = "vertical",
        content_height = 800,
        threshold = 10
    })
    
    -- 标题 - 居中显示
    local title = ui.label({
        x = 85, y = 25,  -- 通过调整x坐标实现居中
        text = "GTFont矢量字体演示",
        color = ui.COLOR_BLACK,
        size = 16
    })
    
    -- 返回按钮
    local btn_back = ui.button({
        x = 20, y = 20,
        w = 60, h = 30,
        text = "返回",
        on_click = function()
            win:back()
        end
    })
    
    -- 动态字体大小演示区域
    local dynamic_title = ui.label({
        x = 20, y = 70,
        text = "GTFont支持动态字体大小调整:",
        color = ui.COLOR_BLACK,
        size = 16
    })
    
    -- 预留足够高度的位置显示当前字体
    local size_display = ui.label({
        x = 20, y = 100,
        text = "当前字体: 16号 蓝色",
        color = ui.COLOR_BLUE,
        size = 16  -- 初始大小
    })
    
    local btn_increase = ui.button({
        x = 20, y = 140,
        w = 120, h = 30,
        text = "点击切换字体大小",
        on_click = function()
            demo_state.current_size = demo_state.current_size + 4
            if demo_state.current_size > 32 then
                demo_state.current_size = 12
            end
            -- 同时更新文本和大小，显示当前颜色
            size_display:set_text("当前字体: " .. demo_state.current_size .. "号 蓝色")
            size_display:set_size(demo_state.current_size)
        end
    })
    
    -- 字体演示标题
    local demo_title = ui.label({
        x = 20, y = 180,
        text = "字体演示:",
        color = ui.COLOR_BLACK,
        size = 16
    })
    
    -- 数字演示 - 蓝色14号
    local number_demo = ui.label({
        x = 20, y = 210,
        text = "1、数字: 0123456789",
        color = ui.COLOR_BLUE,
        size = 14
    })
    
    -- 符号演示 - 橙色20号
    local symbol_demo = ui.label({
        x = 20, y = 250,
        text = "2、符号: !@#$%^&*()_+-=[]",
        color = ui.COLOR_ORANGE,
        size = 20
    })
    
    -- 中英文演示 - 红色28号
    local text_demo = ui.label({
        x = 20, y = 300,
        text = "3、中英文: LuatOS",
        color = ui.COLOR_RED,
        size = 28
    })
    
    -- GTFont特性说明
    local feature_title = ui.label({
        x = 20, y = 350,
        text = "GTFont特性:",
        color = ui.COLOR_BLACK,
        size = 16
    })
    
    -- 特性说明使用14号字体
    local feature1 = ui.label({
        x = 20, y = 380,
        text = "- 使用AirFONTS_1000配件板",
        color = ui.COLOR_GRAY,
        size = 14
    })
    
    local feature2 = ui.label({
        x = 20, y = 410,
        text = "- 支持10到192号的黑体字体",
        color = ui.COLOR_GRAY,
        size = 14
    })
    
    local feature3 = ui.label({
        x = 20, y = 440,
        text = "- 支持GBK中文和ASCII码字符集",
        color = ui.COLOR_GRAY,
        size = 14
    })
    
    local feature4 = ui.label({
        x = 20, y = 470,
        text = "- 支持灰度显示，字体边缘更平滑",
        color = ui.COLOR_GRAY,
        size = 14
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
    win:add(feature_title)
    win:add(feature1)
    win:add(feature2)
    win:add(feature3)
    win:add(feature4)
    
    return win
end

return gtfont_page