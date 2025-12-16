--[[
@module  home_page
@summary 主页模块，基于exEasyUI实现
@version 1.0
@date    2025.12.10
@author  江访
@usage
本文件为exeasyui主程序模块，核心业务逻辑为：
1、设置主题为浅色；
2、进入演示主页面；
3、启用主循环；

本文件没有对外接口；

]]

local home_page = require("home_page")

-- 启动UI主任务
local function ui_main()

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