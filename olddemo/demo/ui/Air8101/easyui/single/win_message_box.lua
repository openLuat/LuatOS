--[[
@module  win_message_box
@summary 消息框组件演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为消息框组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加消息框组件显示通知信息；
3、启用自动换行功能显示长文本；
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

    -- 计算居中位置
    local page_w, page_h = lcd.getSize()
    local message_width = 500
    local message_height = 300
    local message_x = (page_w - message_width) / 2
    local message_y = (page_h - message_height) / 2

    -- 创建消息框组件
    local box = ui.message_box({ 
        x = message_x, y = message_y, 
        w = message_width, h = message_height,
        wordWrap = true,
        title = "通知", 
        message = "愿你前路浩荡,未来可期.愿你保持热爱,奔赴山海。愿你所有的努力都不被辜负,最终活成自己最喜欢的模样.加油!"
    })
    
    -- 添加标题
    local title_label = ui.label({
        x = message_x, y = message_y - 60,
        text = "消息框组件演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(box)

    -- 注册窗口到UI系统
    ui.add(page1)

end

sys.taskInit(ui_main)