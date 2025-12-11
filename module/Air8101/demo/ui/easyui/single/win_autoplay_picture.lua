--[[
@module  win_autoplay_picture
@summary 自动轮播图片演示模块
@version 1.0.0
@date    2025.12.9
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

    local page_w, page_h = lcd.getSize()
    -- 计算居中位置
    local pic_width = 400
    local pic_height = 300
    local pic_x = (page_w - pic_width) / 2
    local pic_y = 100

    -- 创建自动轮播图片组件
    local pic = ui.picture({ 
        x = pic_x, y = pic_y, 
        w = pic_width, h = pic_height,
        sources = {"/luadb/1.jpg", "/luadb/2.jpg", "/luadb/3.jpg"}, 
        autoplay = true, 
        interval = 1500
    })
    
    -- 添加标题
    local title_label = ui.label({
        x = pic_x, y = pic_y - 60,
        text = "图片自动轮播演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加说明标签
    local hint_label = ui.label({
        x = pic_x, y = pic_y + pic_height + 20,
        text = "图片自动切换，间隔1.5秒",
        color = ui.COLOR_GRAY,
        size = 16
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(pic)
    page1:add(hint_label)

    -- 注册窗口到UI系统
    ui.add(page1)

    -- 启动exeasyui刷新主循环
    while true do
        -- 刷新显示
        ui.refresh()
        -- 等待30ms
        sys.wait(30)
    end
end

sys.taskInit(ui_main)