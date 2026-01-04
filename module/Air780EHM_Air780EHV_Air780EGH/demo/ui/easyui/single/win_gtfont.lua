--[[
@module  win_gtfont
@summary GTFont矢量字体演示模块
@version 1.0.0
@date    2025.11.28
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
        spi = { id = 0, cs = 8 }, 
        size = 32 
    })
    
    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local win = ui.window({ background_color = ui.COLOR_WHITE })

    -- 创建多个标签展示不同字体样式
    local text1 = ui.label({ x = 10, y = 20, text = "ABCDEFG", color = ui.COLOR_BLACK })
    local text2 = ui.label({ x = 10, y = 100, text = "abcdefg", color = ui.COLOR_RED })
    local text3 = ui.label({ x = 10, y = 180, text = "1234567", color = ui.COLOR_GREEN })
    local text4 = ui.label({ x = 10, y = 260, text = "!@#$%^&*", color = ui.COLOR_BLUE })
    local text5 = ui.label({ x = 10, y = 340, text = "Hello GTFont", color = ui.COLOR_ORANGE })
    local text6 = ui.label({ x = 10, y = 420, text = "中英混排 ABC 合宙", color = ui.COLOR_PINK })

    -- 添加组件到窗口
    win:add(text1)
    win:add(text2)
    win:add(text3)
    win:add(text4)
    win:add(text5)
    win:add(text6)

    -- 注册窗口到UI系统
    ui.add(win)

end

sys.taskInit(ui_main)