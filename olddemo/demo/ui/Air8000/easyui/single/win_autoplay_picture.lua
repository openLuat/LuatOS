--[[
@module  win_autoplay_picture
@summary 自动轮播图片演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为自动轮播图片演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加图片轮播组件；
3、配置自动播放和切换间隔；
4、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local function ui_main()

    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local page1 = ui.window({ background_color = ui.COLOR_WHITE })

    -- 创建自动轮播图片组件
    local pic = ui.picture({ 
        x = 20, y = 20, 
        sources = {"/luadb/1.jpg", "/luadb/2.jpg", "/luadb/3.jpg"}, 
        autoplay = true, 
        interval = 1500
    })
    
    -- 添加组件到窗口
    page1:add(pic)

    -- 注册窗口到UI系统
    ui.add(page1)

end

sys.taskInit(ui_main)