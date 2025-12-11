--[[
@module  win_input
@summary 文本输入框演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为文本输入框演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加文本输入框组件；
3、设置占位符文本和最大长度限制；
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
    local input_width = 400
    local input_x = (page_w - input_width) / 2

    -- 创建文本输入框组件
    local text_input = ui.input({
        x = input_x, y = 200,
        w = 300, h = 40,
        placeholder = "请输入文本内容...",
        max_length = 50,
        size = 16
    })

    -- 添加标题
    local title_label = ui.label({
        x = input_x, y = 120,
        text = "文本输入框演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加说明标签
    local hint_label = ui.label({
        x = input_x, y = 260,
        text = "最大长度50个字符",
        color = ui.COLOR_GRAY,
        size = 14
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(text_input)
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