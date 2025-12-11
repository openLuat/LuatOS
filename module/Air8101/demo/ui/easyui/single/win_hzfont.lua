--[[
@module  win_hzfont
@summary HzFont矢量字体演示模块（目前Air8101支持HZFont的固件正在开发中）
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为HzFont矢量字体演示模块，核心业务逻辑为：
1、启用14号固件内置HzFont矢量字体方式驱动；
2、创建窗口容器并设置白色背景；
3、添加多个标签组件展示矢量字体特性；
4、演示抗锯齿渲染和智能缓存功能；
5、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local function ui_main()
    -- 启用14号固件内置HzFont矢量字体方式驱动
    hw_font_drv.init({
        type = "hzfont",
        size = 32,
        antialias = -1  -- 自动抗锯齿
    })

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local win = ui.window({ background_color = ui.COLOR_WHITE })

    -- 计算居中位置
    local page_w, page_h = lcd.getSize()
    local container_width = 200
    local container_x = (page_w - container_width) / 2

    -- 创建标题
    local title = ui.label({
        x = container_x,
        y = 30,
        text = "HzFont矢量字体演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 创建多个标签展示矢量字体特性
    local text1 = ui.label({ x = container_x, y = 80, text = "HzFont矢量字体", color = ui.COLOR_BLACK, size = 20 })
    local text2 = ui.label({ x = container_x, y = 120, text = "Hello World", color = ui.COLOR_RED, size = 20 })
    local text3 = ui.label({ x = container_x, y = 160, text = "支持10-100号大小", color = ui.COLOR_GREEN, size = 20 })
    local text4 = ui.label({ x = container_x, y = 200, text = "支持抗锯齿渲染", color = ui.COLOR_BLUE, size = 20 })
    local text5 = ui.label({ x = container_x, y = 240, text = "智能缓存加速", color = ui.COLOR_ORANGE, size = 20 })
    local text6 = ui.label({ x = container_x, y = 280, text = "字形平滑清晰", color = ui.COLOR_PURPLE, size = 20 })
    local text7 = ui.label({ x = container_x, y = 320, text = "支持中文显示", color = ui.COLOR_DARK_GRAY, size = 20 })

    -- 添加组件到窗口
    win:add(title)
    win:add(text1)
    win:add(text2)
    win:add(text3)
    win:add(text4)
    win:add(text5)
    win:add(text6)
    win:add(text7)

    -- 注册窗口到UI系统
    ui.add(win)

    -- 启动exeasyui刷新主循环
    while true do
        ui.refresh()
        sys.wait(30)
    end
end

sys.taskInit(ui_main)
