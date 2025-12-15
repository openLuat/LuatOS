--[[
@module  win_combo_box
@summary 下拉框组件演示模块
@version 1.0.0
@date    2025.12.9
@author  江访
@usage
本文件为下拉框组件演示模块，核心业务逻辑为：
1、创建窗口容器并设置白色背景；
2、添加下拉框组件；
3、配置选项列表和选择回调；
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
    local container_width = 400
    local container_x = (page_w - container_width) / 2

    -- 创建下拉框组件
    local combo_box = ui.combo_box({
        x = container_x, y = 150,
        w = 300, h = 40,
        options = { "选项1", "选项2", "选项3", "选项4", "选项5" },
        placeholder = "请选择",
        selected = 1,
        size = 16,
        on_select = function(value, index, text)
            log.info("combo_box", "选择了:", text, "索引:", index)
        end
    })

    -- 添加标题
    local title_label = ui.label({
        x = container_x, y = 80,
        text = "下拉框组件演示",
        color = ui.COLOR_BLACK,
        size = 24
    })

    -- 添加提示标签
    local hint_label = ui.label({
        x = container_x, y = 210,
        text = "点击下拉箭头选择选项",
        color = ui.COLOR_GRAY,
        size = 14
    })

    -- 添加组件到窗口
    page1:add(title_label)
    page1:add(combo_box)
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