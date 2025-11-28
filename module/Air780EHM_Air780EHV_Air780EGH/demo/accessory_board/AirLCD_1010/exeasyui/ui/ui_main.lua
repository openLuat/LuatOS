--[[
@module  home_page
@summary 主页模块，基于exEasyUI实现
@version 1.0
@date    2025.11.20
@author  江访
]]



local home_page = require("home_page")

-- 启动UI主任务
local function ui_main()
    sys.wait(1000) -- 等待系统稳定
    

    -- 初始化UI主题
    ui.sw_init({ theme = "light" })
    
    home_page.create()

    -- 主渲染循环
    while true do
        ui.refresh()
        sys.wait(30)
    end
end

sys.taskInit(ui_main)