--[[
@module  hzfont_page
@summary HZFont矢量字体演示页面模块，Air8101  HZFont矢量字体正在开发中
@version 1.0
@date    2025.12.2
@author  适配修改
@usage
本文件为HZFont矢量字体演示页面预留模块
]]

local hzfont_page = {}

function hzfont_page.create(ui)
    local win = ui.window({ 
        background_color = ui.COLOR_WHITE,
        x = 0, y = 0, w = 800, h = 480
    })
    
   
    -- 标题
    local title = ui.label({
        x = 300, y = 25,
        text = "HZFont矢量字体目前正在开发中。。。",
        color = ui.COLOR_BLACK,
        size = 20
    })
 -- 返回按钮
    local btn_back = ui.button({
        x = 20, y = 20,
        w = 80, h = 40,
        text = "返回",
        font_size = 14,
        on_click = function()
            win:back()
        end
    })
    
    -- 添加所有组件到窗口
    win:add(title)
    win:add(btn_back)
    
    return win
end

return hzfont_page