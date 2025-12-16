--[[
@module  win_number_input
@summary 数字输入框演示模块
@version 1.0.0
@date    2025.11.28
@author  江访
@usage
本文件为数字输入框演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加数字输入框组件；
3、添加增减按钮控制数字输入；
4、实现数字范围限制功能；
5、启动UI渲染循环持续刷新显示；

本文件没有对外接口；
]]

local function ui_main()  
    -- 显示触摸初始化
    hw_font_drv.init()

    -- 设置主题
    ui.sw_init({ theme = "light" })

    -- 创建窗口容器
    local page1 = ui.window({ background_color = ui.COLOR_WHITE })

    -- 创建数字输入框组件
    local number_input = ui.input({
        x = 20, y = 20,
        w = 100, h = 30,
        placeholder = "0-100",
        input_type = "number",
        max_length = 3
    })

    -- 创建减少按钮
    local btn_number_minus = ui.button({
        x = 130, y = 20,
        w = 40, h = 30,
        text = "-",
        on_click = function()
            local value = tonumber(number_input:get_text()) or 0
            if value > 0 then
                number_input:set_text(tostring(value - 1))
            end
        end
    })

    -- 创建增加按钮
    local btn_number_plus = ui.button({
        x = 180, y = 20,
        w = 40, h = 30,
        text = "+",
        on_click = function()
            local value = tonumber(number_input:get_text()) or 0
            if value < 100 then
                number_input:set_text(tostring(value + 1))
            end
        end
    })

    -- 添加组件到窗口
    page1:add(number_input)
    page1:add(btn_number_minus)
    page1:add(btn_number_plus)

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