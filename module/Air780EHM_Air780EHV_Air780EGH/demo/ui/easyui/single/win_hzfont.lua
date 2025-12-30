--[[
@module  win_hzfont
@summary HzFont矢量字体演示模块
@version 1.0.0
@date    2025.11.28
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
    ui.init({ theme = "light" })

    -- 创建窗口容器
    local win = ui.window({ background_color = ui.COLOR_WHITE })

    -- 创建多个标签展示矢量字体特性
    local text1 = ui.label({ x = 10, y = 20, text = "HzFont矢量字体", color = ui.COLOR_BLACK })
    local text2 = ui.label({ x = 10, y = 60, text = "Hello World", color = ui.COLOR_RED })
    local text3 = ui.label({ x = 10, y = 100, text = "支持10-100号大小", color = ui.COLOR_GREEN })
    local text4 = ui.label({ x = 10, y = 140, text = "支持抗锯齿渲染", color = ui.COLOR_BLUE })
    local text5 = ui.label({ x = 10, y = 180, text = "智能缓存加速", color = ui.COLOR_ORANGE })

    -- 添加组件到窗口
    win:add(text1)
    win:add(text2)
    win:add(text3)
    win:add(text4)
    win:add(text5)

    -- 注册窗口到UI系统
    ui.add(win)

end

sys.taskInit(ui_main)