--[[
@module  win_gtfont
@summary GTFont矢量字体演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为GTFont矢量字体演示模块，核心业务逻辑为：
1、初始化GTFont矢量字体后端，使用外置SPI字库配件板；
2、创建窗口容器并设置白色背景；
3、添加多个标签组件展示不同字体样式；
4、演示中英混排显示效果；
5、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local function ui_main()

    -- 启用GTFont矢量字体方式进行硬件初始化
    hw_font_drv.init({ 
        type = "gtfont", 
        spi = { id = 1, cs = 3 }, 
        size = 32 
    })
    
    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local win = ui.window({ background_color = ui.COLOR_WHITE })

    -- 计算两列布局
    local column_width = 380
    local left_column_x = 40
    local right_column_x = 420
    local row_height = 60
    local start_y = 80

    -- 创建标题
    local title = ui.label({
        x = left_column_x + 200, y = start_y,
        text = "GTFont矢量字体演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 左列标签展示
    local text1 = ui.label({ x = left_column_x, y = start_y + 60, text = "ABCDEFG", color = ui.COLOR_BLACK, size = 22 })
    local text2 = ui.label({ x = left_column_x, y = start_y + 120, text = "abcdefg", color = ui.COLOR_RED, size = 24 })
    local text3 = ui.label({ x = left_column_x, y = start_y + 180, text = "1234567", color = ui.COLOR_GREEN, size = 26 })
    local text4 = ui.label({ x = left_column_x, y = start_y + 240, text = "!@#$%^&*", color = ui.COLOR_BLUE, size = 32 })

    -- 右列标签展示
    local text5 = ui.label({ x = right_column_x, y = start_y + 60, text = "Hello GTFont", color = ui.COLOR_ORANGE, size = 22 })
    local text6 = ui.label({ x = right_column_x, y = start_y + 120, text = "中英混排 ABC 合宙", color = ui.COLOR_PINK, size = 24 })
    local text7 = ui.label({ x = right_column_x, y = start_y + 180, text = "矢量字体清晰", color = ui.COLOR_PURPLE, size = 26 })
    local text8 = ui.label({ x = right_column_x, y = start_y + 240, text = "支持10-192字号", color = ui.COLOR_DARK_GRAY, size = 32 })

    -- 添加组件到窗口
    win:add(title)
    win:add(text1)
    win:add(text2)
    win:add(text3)
    win:add(text4)
    win:add(text5)
    win:add(text6)
    win:add(text7)
    win:add(text8)

    -- 注册窗口到UI系统
    ui.add(win)

end

sys.taskInit(ui_main)